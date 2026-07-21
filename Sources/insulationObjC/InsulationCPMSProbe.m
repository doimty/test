#ifndef INSULATION_CPMS_PROBE_ENABLED
#define INSULATION_CPMS_PROBE_ENABLED 1
#endif

#if INSULATION_CPMS_PROBE_ENABLED

#import "InsulationCPMSProbe.h"

#import <dispatch/dispatch.h>
#import <objc/runtime.h>
#import <stdatomic.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#import "../insulationC/include/Tweak.h"
#import "InsulationPowerHelper.h"

static unsigned (*Orig_CPMSProbe_getMaxPowerForComponent)(id self, SEL _cmd, int component);
static unsigned (*Orig_CPMSProbe_getMinPowerForComponent)(id self, SEL _cmd, int component);

static BOOL InsulationCPMSProbeMaxEverInstalled;
static BOOL InsulationCPMSProbeMinEverInstalled;

static atomic_uint_fast64_t InsulationCPMSProbeMaxCallCount = ATOMIC_VAR_INIT(0);
static atomic_uint_fast64_t InsulationCPMSProbeMinCallCount = ATOMIC_VAR_INIT(0);
static atomic_int InsulationCPMSProbeLastMaxComponent = ATOMIC_VAR_INIT(0);
static atomic_int InsulationCPMSProbeLastMinComponent = ATOMIC_VAR_INIT(0);
static atomic_uint InsulationCPMSProbeLastMaxResult = ATOMIC_VAR_INIT(0);
static atomic_uint InsulationCPMSProbeLastMinResult = ATOMIC_VAR_INIT(0);
static atomic_bool InsulationCPMSProbeFlushScheduled = ATOMIC_VAR_INIT(false);

static NSDictionary *InsulationCPMSProbeInstallMetadata;
static const NSTimeInterval InsulationCPMSProbeRetryOffsets[] = { 0.0, 0.25, 1.0, 3.0 };

static dispatch_queue_t InsulationCPMSProbeQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        queue = dispatch_queue_create("com.be-huge.insulation.cpms-probe", DISPATCH_QUEUE_SERIAL);
    });
    return queue;
}

static NSArray<NSString *> *InsulationCPMSProbePaths(void) {
    NSString *primary = rootlessPath(@"/var/mobile/Library/Preferences/com.be-huge.insulation-cpms-probe.plist");
    NSArray<NSString *> *candidates = @[
        primary,
        @"/var/mobile/Library/Preferences/com.be-huge.insulation-cpms-probe.plist",
        @"/tmp/com.be-huge.insulation-cpms-probe.plist",
    ];
    NSMutableArray<NSString *> *paths = [NSMutableArray array];
    for (NSString *path in candidates) {
        if ([path isKindOfClass:[NSString class]] && [path length] > 0 && ![paths containsObject:path]) {
            [paths addObject:path];
        }
    }
    return paths;
}

static NSDictionary *InsulationCPMSProbeWriteSnapshotData(NSDictionary *snapshot,
                                                            NSArray<NSString *> *paths) {
    NSError *serializationError = nil;
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:snapshot
                                                              format:NSPropertyListBinaryFormat_v1_0
                                                             options:0
                                                               error:&serializationError];
    NSMutableDictionary *pathResults = [NSMutableDictionary dictionary];
    if (!data) {
        NSMutableDictionary *result = [@{ @"success": @NO } mutableCopy];
        if (serializationError) {
            result[@"errorDomain"] = serializationError.domain ?: @"";
            result[@"errorCode"] = @(serializationError.code);
            result[@"errorDescription"] = serializationError.localizedDescription ?: @"";
        }
        pathResults[@"<serialization>"] = result;
        return @{ @"anySucceeded": @NO, @"paths": pathResults };
    }

    BOOL anySucceeded = NO;
    for (NSString *path in paths) {
        NSError *writeError = nil;
        BOOL success = [data writeToFile:path options:NSDataWritingAtomic error:&writeError];
        NSMutableDictionary *result = [@{ @"success": @(success) } mutableCopy];
        if (writeError) {
            result[@"errorDomain"] = writeError.domain ?: @"";
            result[@"errorCode"] = @(writeError.code);
            result[@"errorDescription"] = writeError.localizedDescription ?: @"";
        }
        pathResults[path] = result;
        anySucceeded = anySucceeded || success;
    }
    return @{ @"anySucceeded": @(anySucceeded), @"paths": pathResults };
}

static void InsulationCPMSProbeWriteSnapshot(void) {
    NSMutableDictionary *snapshot = [NSMutableDictionary dictionaryWithDictionary:InsulationCPMSProbeInstallMetadata ?: @{}];
    uint64_t maxCount = atomic_load_explicit(&InsulationCPMSProbeMaxCallCount, memory_order_relaxed);
    uint64_t minCount = atomic_load_explicit(&InsulationCPMSProbeMinCallCount, memory_order_relaxed);

    NSMutableDictionary *maxCalls = [@{ @"count": @(maxCount) } mutableCopy];
    if (maxCount > 0) {
        maxCalls[@"lastComponent"] = @(atomic_load_explicit(&InsulationCPMSProbeLastMaxComponent, memory_order_relaxed));
        maxCalls[@"lastResult"] = @(atomic_load_explicit(&InsulationCPMSProbeLastMaxResult, memory_order_relaxed));
    }

    NSMutableDictionary *minCalls = [@{ @"count": @(minCount) } mutableCopy];
    if (minCount > 0) {
        minCalls[@"lastComponent"] = @(atomic_load_explicit(&InsulationCPMSProbeLastMinComponent, memory_order_relaxed));
        minCalls[@"lastResult"] = @(atomic_load_explicit(&InsulationCPMSProbeLastMinResult, memory_order_relaxed));
    }

    NSArray<NSString *> *paths = InsulationCPMSProbePaths();
    snapshot[@"calls"] = @{
        @"getMaxPowerForComponent:": maxCalls,
        @"getMinPowerForComponent:": minCalls,
    };
    snapshot[@"lastWriteAt"] = @([[NSDate date] timeIntervalSince1970]);
    snapshot[@"writePaths"] = paths;
    snapshot[@"writeStatus"] = @"pending";

    NSDictionary *writeResults = InsulationCPMSProbeWriteSnapshotData(snapshot, paths);
    BOOL anySucceeded = [writeResults[@"anySucceeded"] boolValue];
    snapshot[@"writeResults"] = writeResults;
    snapshot[@"writeStatus"] = anySucceeded ? @"written" : @"failed";
    if (anySucceeded) {
        InsulationCPMSProbeWriteSnapshotData(snapshot, paths);
    } else {
        NSLog(@"[InsulationCPMSProbe] snapshot write failed: %@", writeResults);
    }
}

static BOOL InsulationCPMSProbeCountIsPowerOfTwo(uint64_t count) {
    return count != 0 && (count & (count - 1)) == 0;
}

static void InsulationCPMSProbeScheduleFlush(uint64_t count) {
    if (!InsulationCPMSProbeCountIsPowerOfTwo(count)) {
        return;
    }

    bool expected = false;
    if (!atomic_compare_exchange_strong_explicit(&InsulationCPMSProbeFlushScheduled,
                                                  &expected,
                                                  true,
                                                  memory_order_relaxed,
                                                  memory_order_relaxed)) {
        return;
    }

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), InsulationCPMSProbeQueue(), ^{
        InsulationCPMSProbeWriteSnapshot();
        atomic_store_explicit(&InsulationCPMSProbeFlushScheduled, false, memory_order_relaxed);
    });
}

static void InsulationCPMSProbeRecordMaxCall(int component, unsigned result) {
    atomic_store_explicit(&InsulationCPMSProbeLastMaxComponent, component, memory_order_relaxed);
    atomic_store_explicit(&InsulationCPMSProbeLastMaxResult, result, memory_order_relaxed);
    uint64_t count = atomic_fetch_add_explicit(&InsulationCPMSProbeMaxCallCount, 1, memory_order_relaxed) + 1;
    InsulationCPMSProbeScheduleFlush(count);
}

static void InsulationCPMSProbeRecordMinCall(int component, unsigned result) {
    atomic_store_explicit(&InsulationCPMSProbeLastMinComponent, component, memory_order_relaxed);
    atomic_store_explicit(&InsulationCPMSProbeLastMinResult, result, memory_order_relaxed);
    uint64_t count = atomic_fetch_add_explicit(&InsulationCPMSProbeMinCallCount, 1, memory_order_relaxed) + 1;
    InsulationCPMSProbeScheduleFlush(count);
}

static unsigned Insulation_CPMSProbe_getMaxPowerForComponent(id self, SEL _cmd, int component) {
    unsigned original = Orig_CPMSProbe_getMaxPowerForComponent(self, _cmd, component);
    InsulationCPMSProbeRecordMaxCall(component, original);
    return InsulationUnrestrictedPowerLimitUInt32();
}

static unsigned Insulation_CPMSProbe_getMinPowerForComponent(id self, SEL _cmd, int component) {
    unsigned original = Orig_CPMSProbe_getMinPowerForComponent(self, _cmd, component);
    InsulationCPMSProbeRecordMinCall(component, original);
    return 0;
}

static Method InsulationCPMSProbeDirectInstanceMethod(Class cls, SEL selector) {
    if (!cls || !selector) {
        return NULL;
    }

    unsigned int methodCount = 0;
    Method *methods = class_copyMethodList(cls, &methodCount);
    Method result = NULL;
    for (unsigned int index = 0; index < methodCount; index++) {
        if (method_getName(methods[index]) == selector) {
            result = methods[index];
            break;
        }
    }
    free(methods);
    return result;
}

static NSString *InsulationCPMSProbeString(const char *value) {
    return value ? [NSString stringWithUTF8String:value] : @"";
}

static char InsulationCPMSProbeBaseType(const char *type) {
    if (!type) {
        return '\0';
    }
    while (*type && strchr("rnNoORV", *type)) {
        type++;
    }
    return *type;
}

static NSMutableDictionary *InsulationCPMSProbeInspectMethod(Class cls,
                                                              SEL selector,
                                                              Method *directMethodOut,
                                                              BOOL *abiMatchesOut) {
    Method visibleMethod = cls ? class_getInstanceMethod(cls, selector) : NULL;
    Method directMethod = InsulationCPMSProbeDirectInstanceMethod(cls, selector);
    Method inspectedMethod = directMethod ?: visibleMethod;
    NSMutableDictionary *metadata = [NSMutableDictionary dictionary];
    metadata[@"selector"] = NSStringFromSelector(selector);
    metadata[@"selectorFound"] = @(visibleMethod != NULL);
    metadata[@"declaredOnCPMSHelper"] = @(directMethod != NULL);

    BOOL abiMatches = NO;
    if (inspectedMethod) {
        const char *typeEncoding = method_getTypeEncoding(inspectedMethod);
        char *returnType = method_copyReturnType(inspectedMethod);
        unsigned int argumentCount = method_getNumberOfArguments(inspectedMethod);
        char *selfType = argumentCount > 0 ? method_copyArgumentType(inspectedMethod, 0) : NULL;
        char *selectorType = argumentCount > 1 ? method_copyArgumentType(inspectedMethod, 1) : NULL;
        char *componentType = argumentCount > 2 ? method_copyArgumentType(inspectedMethod, 2) : NULL;

        metadata[@"typeEncoding"] = InsulationCPMSProbeString(typeEncoding);
        metadata[@"returnType"] = InsulationCPMSProbeString(returnType);
        metadata[@"selfArgumentType"] = InsulationCPMSProbeString(selfType);
        metadata[@"selectorArgumentType"] = InsulationCPMSProbeString(selectorType);
        metadata[@"componentArgumentType"] = InsulationCPMSProbeString(componentType);
        metadata[@"argumentCount"] = @(argumentCount);

        abiMatches = directMethod != NULL &&
                     argumentCount == 3 &&
                     InsulationCPMSProbeBaseType(returnType) == 'I' &&
                     InsulationCPMSProbeBaseType(selfType) == '@' &&
                     InsulationCPMSProbeBaseType(selectorType) == ':' &&
                     InsulationCPMSProbeBaseType(componentType) == 'i';
        free(returnType);
        free(selfType);
        free(selectorType);
        free(componentType);
    }

    metadata[@"abiMatchesUnsignedIntComponent"] = @(abiMatches);
    metadata[@"hookInstalled"] = @NO;
    if (directMethodOut) {
        *directMethodOut = directMethod;
    }
    if (abiMatchesOut) {
        *abiMatchesOut = abiMatches;
    }
    return metadata;
}

static BOOL InsulationCPMSProbeInstallMethod(Method method, IMP replacement, IMP *originalOut) {
    if (!method || !replacement || !originalOut) {
        return NO;
    }

    IMP original = method_getImplementation(method);
    if (!original) {
        return NO;
    }
    if (original == replacement) {
        return *originalOut != NULL;
    }

    *originalOut = original;
    IMP replaced = method_setImplementation(method, replacement);
    if (replaced && replaced != original) {
        *originalOut = replaced;
    }
    return method_getImplementation(method) == replacement;
}

static BOOL InsulationCPMSProbeInspectAndInstall(NSUInteger attempt) {
    Class cpmsClass = objc_getClass("CPMSHelper");
    SEL maxSelector = sel_registerName("getMaxPowerForComponent:");
    SEL minSelector = sel_registerName("getMinPowerForComponent:");
    Method maxMethod = NULL;
    Method minMethod = NULL;
    BOOL maxABIMatches = NO;
    BOOL minABIMatches = NO;

    NSMutableDictionary *maxMetadata = InsulationCPMSProbeInspectMethod(cpmsClass,
                                                                        maxSelector,
                                                                        &maxMethod,
                                                                        &maxABIMatches);
    NSMutableDictionary *minMetadata = InsulationCPMSProbeInspectMethod(cpmsClass,
                                                                        minSelector,
                                                                        &minMethod,
                                                                        &minABIMatches);

    BOOL maxInstalled = maxABIMatches && InsulationCPMSProbeInstallMethod(maxMethod,
                                                                          (IMP)Insulation_CPMSProbe_getMaxPowerForComponent,
                                                                          (IMP *)&Orig_CPMSProbe_getMaxPowerForComponent);
    BOOL minInstalled = minABIMatches && InsulationCPMSProbeInstallMethod(minMethod,
                                                                          (IMP)Insulation_CPMSProbe_getMinPowerForComponent,
                                                                          (IMP *)&Orig_CPMSProbe_getMinPowerForComponent);
    InsulationCPMSProbeMaxEverInstalled = InsulationCPMSProbeMaxEverInstalled || maxInstalled;
    InsulationCPMSProbeMinEverInstalled = InsulationCPMSProbeMinEverInstalled || minInstalled;
    maxMetadata[@"hookInstalled"] = @(maxInstalled);
    maxMetadata[@"everInstalled"] = @(InsulationCPMSProbeMaxEverInstalled);
    minMetadata[@"hookInstalled"] = @(minInstalled);
    minMetadata[@"everInstalled"] = @(InsulationCPMSProbeMinEverInstalled);

    InsulationCPMSProbeInstallMetadata = @{
        @"schemaVersion": @2,
        @"probeVersion": @"cpms-abi-raise-1",
        @"mode": @"raise",
        @"unrestrictedPowerTarget": @(InsulationUnrestrictedPowerLimitUInt32()),
        @"pid": @((int)[[NSProcessInfo processInfo] processIdentifier]),
        @"lastInstallAttemptAt": @([[NSDate date] timeIntervalSince1970]),
        @"installAttempt": @(attempt),
        @"className": @"CPMSHelper",
        @"classFound": @(cpmsClass != Nil),
        @"expectedABI": @{
            @"returnType": @"unsigned int (I)",
            @"selfArgumentType": @"object (@)",
            @"selectorArgumentType": @"selector (:)",
            @"componentArgumentType": @"int (i)",
            @"argumentCount": @3,
        },
        @"methods": @{
            @"getMaxPowerForComponent:": maxMetadata,
            @"getMinPowerForComponent:": minMetadata,
        },
    };
    InsulationCPMSProbeWriteSnapshot();
    return maxInstalled && minInstalled;
}

static void InsulationCPMSProbeRunInstallAttempt(NSUInteger attempt) {
    if (InsulationCPMSProbeMaxEverInstalled && InsulationCPMSProbeMinEverInstalled) {
        return;
    }
    InsulationCPMSProbeInspectAndInstall(attempt);
}

void InsulationCPMSProbeInstall(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSUInteger attemptCount = sizeof(InsulationCPMSProbeRetryOffsets) / sizeof(InsulationCPMSProbeRetryOffsets[0]);
        for (NSUInteger attempt = 0; attempt < attemptCount; attempt++) {
            NSTimeInterval offset = InsulationCPMSProbeRetryOffsets[attempt];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(offset * NSEC_PER_SEC)),
                           InsulationCPMSProbeQueue(), ^{
                InsulationCPMSProbeRunInstallAttempt(attempt);
            });
        }
    });
}

#endif
