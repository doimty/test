#define INSULATION_PROBE_IMPLEMENTATION 1
#import "InsulationMachIOProbe.h"

#if INSULATION_PROBE_ENABLED

#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import <IOKit/IOKitLib.h>
#import <mach/mach_time.h>
#import <substrate.h>
#import <notify.h>
#import <dlfcn.h>

/* ── Ring buffer (lock-free, 256 entries, C-only hot path) ── */

#define MACHIO_RING_SIZE 256
#define MACHIO_PNAME_MAX 48

struct machio_entry {
    uint64_t   mono_time;       /* mach_continuous_time */
    uint32_t   selector;        /* IOConnectCallScalarMethod selector */
    uint64_t   connection;      /* mach_port_t (io_connect_t) */
    uint64_t   input0;          /* first scalar input */
    uint64_t   input1;          /* second scalar input */
    uint64_t   input2;          /* third scalar input */
    uint32_t   input_cnt;       /* number of scalar inputs */
    bool       is_call_method;  /* true if via IOConnectCallMethod, false if scalar */
    bool       valid;
};

static struct machio_entry machio_ring[MACHIO_RING_SIZE];
static volatile uint32_t machio_ring_head;
static volatile uint32_t machio_ring_count;
static bool machio_hooks_installed;
static char machio_process_name[MACHIO_PNAME_MAX];

/* ── Original function pointers ── */

static kern_return_t (*orig_IOConnectCallScalarMethod)(mach_port_t connection, uint32_t selector,
    const uint64_t *input, uint32_t inputCnt, uint64_t *output, uint32_t *outputCnt);

static kern_return_t (*orig_IOConnectCallMethod)(mach_port_t connection, uint32_t selector,
    const uint64_t *input, uint32_t inputCnt, const void *inputStruct, size_t inputStructCnt,
    uint64_t *output, uint32_t *outputCnt, void *outputStruct, size_t *outputStructCnt);

/* ── Hooked IOConnectCallScalarMethod ── */

static kern_return_t hooked_IOConnectCallScalarMethod(mach_port_t connection, uint32_t selector,
    const uint64_t *input, uint32_t inputCnt, uint64_t *output, uint32_t *outputCnt) {
    
    uint32_t idx = __sync_fetch_and_add(&machio_ring_head, 1) % MACHIO_RING_SIZE;
    struct machio_entry *e = &machio_ring[idx];
    e->mono_time = mach_continuous_time();
    e->selector = selector;
    e->connection = (uint64_t)connection;
    e->input0 = (input && inputCnt > 0) ? input[0] : 0;
    e->input1 = (input && inputCnt > 1) ? input[1] : 0;
    e->input2 = (input && inputCnt > 2) ? input[2] : 0;
    e->input_cnt = inputCnt;
    e->is_call_method = false;
    e->valid = true;
    __sync_fetch_and_add(&machio_ring_count, 1);
    
    return orig_IOConnectCallScalarMethod(connection, selector, input, inputCnt, output, outputCnt);
}

/* ── Hooked IOConnectCallMethod ── */

static kern_return_t hooked_IOConnectCallMethod(mach_port_t connection, uint32_t selector,
    const uint64_t *input, uint32_t inputCnt, const void *inputStruct, size_t inputStructCnt,
    uint64_t *output, uint32_t *outputCnt, void *outputStruct, size_t *outputStructCnt) {
    
    uint32_t idx = __sync_fetch_and_add(&machio_ring_head, 1) % MACHIO_RING_SIZE;
    struct machio_entry *e = &machio_ring[idx];
    e->mono_time = mach_continuous_time();
    e->selector = selector;
    e->connection = (uint64_t)connection;
    e->input0 = (input && inputCnt > 0) ? input[0] : 0;
    e->input1 = (input && inputCnt > 1) ? input[1] : 0;
    e->input2 = (input && inputCnt > 2) ? input[2] : 0;
    e->input_cnt = inputCnt;
    e->is_call_method = true;
    e->valid = true;
    __sync_fetch_and_add(&machio_ring_count, 1);
    
    return orig_IOConnectCallMethod(connection, selector, input, inputCnt, inputStruct, inputStructCnt,
        output, outputCnt, outputStruct, outputStructCnt);
}

/* ── Snapshot: dump ring buffer as NSArray ── */

NSArray *InsulationMachIOProbeSnapshot(void) {
    uint32_t head = machio_ring_head;
    uint32_t count = machio_ring_count;
    uint32_t entries = (count > MACHIO_RING_SIZE) ? MACHIO_RING_SIZE : count;
    uint32_t start = (count > MACHIO_RING_SIZE) ? (head - MACHIO_RING_SIZE) : 0;
    
    NSMutableArray *result = [NSMutableArray arrayWithCapacity:entries];
    for (uint32_t i = 0; i < entries; i++) {
        uint32_t idx = (start + i) % MACHIO_RING_SIZE;
        struct machio_entry *e = &machio_ring[idx];
        if (!e->valid) continue;
        
        NSMutableDictionary *d = [NSMutableDictionary dictionary];
        d[@"monoTime"] = @((unsigned long long)e->mono_time);
        d[@"selector"] = @(e->selector);
        d[@"connection"] = @((unsigned long long)e->connection);
        d[@"input0"] = @((unsigned long long)e->input0);
        d[@"input1"] = @((unsigned long long)e->input1);
        d[@"input2"] = @((unsigned long long)e->input2);
        d[@"inputCnt"] = @(e->input_cnt);
        d[@"isCallMethod"] = @(e->is_call_method);
        [result addObject:d];
    }
    return result;
}

/* ── Plist writer (process-specific, async) ── */

static NSString *InsulationMachIOProbePlistPath(void) {
    /* Use process name to avoid collisions */
    NSString *procName = [NSString stringWithUTF8String:machio_process_name];
    return [NSString stringWithFormat:@"/var/mobile/Library/Preferences/com.be-huge.insulation-machio-probe.%@.plist", procName];
}

static void InsulationMachIOProbeWriteSnapshot(void) {
    NSArray *snapshot = InsulationMachIOProbeSnapshot();
    if ([snapshot count] == 0) return;
    
    NSDictionary *plist = @{
        @"schemaVersion": @1,
        @"processName": [NSString stringWithUTF8String:machio_process_name],
        @"pid": @((int)[[NSProcessInfo processInfo] processIdentifier]),
        @"recordedAt": @([[NSDate date] timeIntervalSince1970]),
        @"ringCount": @((unsigned long long)machio_ring_count),
        @"entries": snapshot,
    };
    
    NSString *path = InsulationMachIOProbePlistPath();
    NSError *error = nil;
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:plist
                                                               format:NSPropertyListBinaryFormat_v1_0
                                                              options:0
                                                                error:&error];
    if (data) {
        [data writeToFile:path options:NSDataWritingAtomic error:&error];
    }
}

/* ── Marker notification callback ── */

static void InsulationMachIOProbeMarkerCallback(CFNotificationCenterRef center,
                                                  void *observer,
                                                  CFStringRef name,
                                                  const void *object,
                                                  CFDictionaryRef userInfo) {
    (void)center;
    (void)observer;
    (void)name;
    (void)object;
    (void)userInfo;
    
    /* Check if this is our marker */
    int token = -1;
    int status = notify_register_check("com.be-huge.insulation.decisionProbe.mark.downclock", &token);
    uint64_t state = 0;
    if (status == NOTIFY_STATUS_OK) {
        notify_get_state(token, &state);
    }
    BOOL valid = (status == NOTIFY_STATUS_OK && state == 0x494E53554D41524BULL); /* 'INSUMARK' */
    if (valid) {
        notify_set_state(token, 0);
    }
    if (token >= 0) notify_cancel(token);
    
    if (valid) {
        /* Write mach IO ring buffer snapshot to process-specific plist */
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            InsulationMachIOProbeWriteSnapshot();
        });
    }
}

/* ── Install hooks via MSHookFunction ── */

void InsulationMachIOProbeInstall(void) {
    if (machio_hooks_installed) return;
    machio_hooks_installed = true;
    
    /* Capture process name */
    const char *procName = [[[NSProcessInfo processInfo] processName] UTF8String];
    if (procName) {
        strncpy(machio_process_name, procName, MACHIO_PNAME_MAX - 1);
        machio_process_name[MACHIO_PNAME_MAX - 1] = '\0';
    }
    
    /* Clear ring buffer */
    memset(machio_ring, 0, sizeof(machio_ring));
    machio_ring_head = 0;
    machio_ring_count = 0;
    
    /* Resolve symbols via dlsym (safe for MSHookFunction input, even on arm64e) */
    void *scalarMethodPtr = dlsym(RTLD_DEFAULT, "IOConnectCallScalarMethod");
    void *callMethodPtr = dlsym(RTLD_DEFAULT, "IOConnectCallMethod");
    
    BOOL scalarHooked = NO;
    BOOL methodHooked = NO;
    
    if (scalarMethodPtr) {
        MSHookFunction(scalarMethodPtr,
                       (void *)hooked_IOConnectCallScalarMethod,
                       (void **)&orig_IOConnectCallScalarMethod);
        scalarHooked = YES;
    }
    
    if (callMethodPtr) {
        MSHookFunction(callMethodPtr,
                       (void *)hooked_IOConnectCallMethod,
                       (void **)&orig_IOConnectCallMethod);
        methodHooked = YES;
    }
    
    /* Register marker notification */
    CFNotificationCenterRef center = CFNotificationCenterGetDarwinNotifyCenter();
    CFNotificationCenterAddObserver(center,
                                    NULL,
                                    InsulationMachIOProbeMarkerCallback,
                                    CFSTR("com.be-huge.insulation.decisionProbe.mark.downclock"),
                                    NULL,
                                    CFNotificationSuspensionBehaviorDeliverImmediately);
    
    // Write a startup marker so we know the process was loaded
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSDictionary *startup = @{
            @"schemaVersion": @1,
            @"processName": [NSString stringWithUTF8String:machio_process_name],
            @"pid": @((int)[[NSProcessInfo processInfo] processIdentifier]),
            @"recordedAt": @([[NSDate date] timeIntervalSince1970]),
            @"event": @"startup",
            @"scalarMethodHooked": @(scalarHooked),
            @"callMethodHooked": @(methodHooked),
            @"entries": @[],
        };
        NSString *path = InsulationMachIOProbePlistPath();
        NSData *data = [NSPropertyListSerialization dataWithPropertyList:startup
                                                                   format:NSPropertyListBinaryFormat_v1_0
                                                                  options:0
                                                                    error:nil];
        if (data) {
            [data writeToFile:path options:NSDataWritingAtomic error:nil];
        }
    });
}

#else

void InsulationMachIOProbeInstall(void) { }

#endif