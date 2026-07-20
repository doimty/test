#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import <IOKit/IOKitLib.h>
#import <mach/mach_time.h>
#import <substrate.h>
#import "../insulationObjC/InsulationProbe.h"
#import "include/Tweak.h"

/* ── Ring buffer (lock-free, 128 entries, C-only hot path) ── */

#define IOKIT_RING_SIZE 128
#define IOKIT_KEY_MAX    64
#define IOKIT_VAL_STR_MAX 64

struct iokit_write_entry {
    uint64_t   mono_time;       /* mach_continuous_time */
    uint64_t   entry;           /* io_registry_entry_t (mach_port_t) */
    char       key[IOKIT_KEY_MAX];
    int64_t    val_int;         /* CFNumber value (if applicable) */
    uint32_t   val_type;        /* CFNumberType if CFNumber, else 0 */
    bool       is_cfproperties; /* true if called via SetCFProperties */
    bool       valid;
};

static struct iokit_write_entry iokit_ring[IOKIT_RING_SIZE];
static volatile uint32_t iokit_ring_head;
static volatile uint32_t iokit_ring_count;
static bool iokit_hooks_installed;

/* ── Original function pointers ── */

static kern_return_t (*orig_IORegistryEntrySetCFProperty)(io_registry_entry_t entry, CFStringRef key, CFTypeRef value);
static kern_return_t (*orig_IORegistryEntrySetCFProperties)(io_registry_entry_t entry, CFTypeRef properties);

/* ── Hooked implementations ── */

static kern_return_t hooked_IORegistryEntrySetCFProperty(io_registry_entry_t entry, CFStringRef key, CFTypeRef value) {
    /* Record before calling original - minimal work on hot path */
    uint32_t idx = __sync_fetch_and_add(&iokit_ring_head, 1) % IOKIT_RING_SIZE;
    struct iokit_write_entry *e = &iokit_ring[idx];
    e->mono_time = mach_continuous_time();
    e->entry = (uint64_t)entry;
    e->is_cfproperties = false;
    e->valid = true;

    if (key && CFStringGetCString(key, e->key, IOKIT_KEY_MAX, kCFStringEncodingUTF8)) {
        /* key copied */
    } else {
        e->key[0] = '\0';
    }

    if (value && CFGetTypeID(value) == CFNumberGetTypeID()) {
        e->val_type = (uint32_t)CFNumberGetType((CFNumberRef)value);
        CFNumberGetValue((CFNumberRef)value, kCFNumberSInt64Type, &e->val_int);
    } else {
        e->val_type = 0;
        e->val_int = 0;
    }

    __sync_fetch_and_add(&iokit_ring_count, 1);

    return orig_IORegistryEntrySetCFProperty(entry, key, value);
}

static kern_return_t hooked_IORegistryEntrySetCFProperties(io_registry_entry_t entry, CFTypeRef properties) {
    uint32_t idx = __sync_fetch_and_add(&iokit_ring_head, 1) % IOKIT_RING_SIZE;
    struct iokit_write_entry *e = &iokit_ring[idx];
    e->mono_time = mach_continuous_time();
    e->entry = (uint64_t)entry;
    e->is_cfproperties = true;
    e->valid = true;
    e->key[0] = '\0';
    e->val_type = 0;
    e->val_int = 0;

    /* Try to extract a summary key from the dictionary */
    if (properties && CFGetTypeID(properties) == CFDictionaryGetTypeID()) {
        CFDictionaryRef dict = (CFDictionaryRef)properties;
        CFIndex count = CFDictionaryGetCount(dict);
        e->val_int = (int64_t)count; /* record number of entries in bulk write */
        /* Copy the first key for debugging */
        if (count > 0) {
            CFStringRef firstKey = NULL;
            CFDictionaryGetKeysAndValues(dict, (const void **)&firstKey, NULL);
            if (firstKey && CFGetTypeID(firstKey) == CFStringGetTypeID()) {
                CFStringGetCString(firstKey, e->key, IOKIT_KEY_MAX, kCFStringEncodingUTF8);
            }
        }
    }

    __sync_fetch_and_add(&iokit_ring_count, 1);

    return orig_IORegistryEntrySetCFProperties(entry, properties);
}

/* ── Snapshot: dump ring buffer as NSArray for plist inclusion ── */

NSArray *InsulationProbeIOKitSnapshot(void) {
    uint32_t head = iokit_ring_head;
    uint32_t count = iokit_ring_count;
    uint32_t start = (count > IOKIT_RING_SIZE) ? (head - IOKIT_RING_SIZE) : 0;
    uint32_t entries = (count > IOKIT_RING_SIZE) ? IOKIT_RING_SIZE : count;

    NSMutableArray *result = [NSMutableArray arrayWithCapacity:entries];
    for (uint32_t i = 0; i < entries; i++) {
        uint32_t idx = (start + i) % IOKIT_RING_SIZE;
        struct iokit_write_entry *e = &iokit_ring[idx];
        if (!e->valid) continue;

        NSMutableDictionary *d = [NSMutableDictionary dictionary];
        d[@"monoTime"] = @((unsigned long long)e->mono_time);
        d[@"entry"] = @((unsigned long long)e->entry);
        d[@"isCFProperties"] = @(e->is_cfproperties);
        if (e->key[0]) d[@"key"] = [NSString stringWithUTF8String:e->key];
        if (e->val_type) {
            d[@"valType"] = @(e->val_type);
            d[@"valInt"] = @(e->val_int);
        }
        [result addObject:d];
    }
    return result;
}

/* ── Install hooks ── */

void InsulationProbeIOKitInstall(void) {
    if (iokit_hooks_installed) return;
    iokit_hooks_installed = true;

    /* Clear ring buffer */
    memset(iokit_ring, 0, sizeof(iokit_ring));
    iokit_ring_head = 0;
    iokit_ring_count = 0;

    /* Hook IORegistryEntrySetCFProperty */
    MSHookFunction((void *)IORegistryEntrySetCFProperty,
                   (void *)hooked_IORegistryEntrySetCFProperty,
                   (void **)&orig_IORegistryEntrySetCFProperty);

    /* Hook IORegistryEntrySetCFProperties */
    MSHookFunction((void *)IORegistryEntrySetCFProperties,
                   (void *)hooked_IORegistryEntrySetCFProperties,
                   (void **)&orig_IORegistryEntrySetCFProperties);

    NSLog(@"insulation: IOKit probe hooks installed (ring %d)", IOKIT_RING_SIZE);
}