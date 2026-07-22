// Generic foreground-app diagnostic probe.
// Hot hooks only touch fixed atomic counters. Snapshot serialization and disk
// I/O stay on the dedicated queue at foreground start/end or an explicit marker.

#import <mach/mach_time.h>
#import <mach-o/dyld.h>
#import <pthread.h>
#import <sched.h>
#import <unistd.h>

static NSString * const PMFGProbeMarkerNotification = @"com.doimty.promotion120.probe.mark.drop";
enum {
    PMFGProbeMarkerIdle = 0,
    PMFGProbeMarkerPublished = 1,
    PMFGProbeMarkerQueued = 2,
};
static dispatch_queue_t PMFGProbeSnapshotQueue = nil;
static NSString *PMFGProbeBundleID = nil;
static NSString *PMFGProbeAppShortVersion = nil;
static NSString *PMFGProbeAppBuildVersion = nil;
static NSString *PMFGProbeDisplayName = nil;
static NSString *PMFGProbeExecutableName = nil;
static CFAbsoluteTime PMFGProbeLoadedWallTime = 0;
static uint64_t PMFGProbeLoadedTicks = 0;
static mach_timebase_info_data_t PMFGProbeTimebase = {0, 0};
static uint64_t PMFGProbeTenMsTicks = 0;
static uint64_t PMFGProbeTwentyMsTicks = 0;
static uint64_t PMFGProbeFortyMsTicks = 0;

static uint32_t PMFGProbeAppActive = 0;
static uint32_t PMFGProbeWriters = 0;
static pthread_mutex_t PMFGProbeMarkerMutex = PTHREAD_MUTEX_INITIALIZER;
static uint32_t PMFGProbeMarkerState = PMFGProbeMarkerIdle;
static uint64_t PMFGProbeMarkerAcceptedGeneration = 0;
static uint64_t PMFGProbeMarkerAcceptedTicks = 0;
static uint64_t PMFGProbeMarkerAcceptedWallMillis = 0;
static uint64_t PMFGProbeMarkerAcceptedToken = 0;
static uint64_t PMFGProbeSessionGeneration = 0;
static uint64_t PMFGProbeSnapshotSequence = 0;
static uint64_t PMFGProbeSessionStartTicks = 0;
static uint64_t PMFGProbeSessionStartWallMillis = 0;

static uint64_t PMFGProbeDisplayLinkCreateCount = 0;
static uint64_t PMFGProbeDisplayLinkRangeCount = 0;
static uint64_t PMFGProbeCAAnimationRangeCount = 0;
static uint64_t PMFGProbeRangeBelow120Count = 0;
static uint64_t PMFGProbeScrollOffsetCount = 0;
static uint64_t PMFGProbeScrollAnimatedCount = 0;
static uint64_t PMFGProbeScrollLayoutMovingCount = 0;
static uint64_t PMFGProbeMetalDrawablePresentCount = 0;
static uint64_t PMFGProbeMetalCommandPresentCount = 0;
static uint64_t PMFGProbeSourceRefreshCount = 0;

static uint64_t PMFGProbeLastRangeSequence = 0;
static uint32_t PMFGProbeLastRangeSource = PMFGProbeRangeSourceNone;
static int32_t PMFGProbeLastRangeMinimumMilli = 0;
static int32_t PMFGProbeLastRangePreferredMilli = 0;
static int32_t PMFGProbeLastRangeMaximumMilli = 0;
static uint64_t PMFGProbeLastRangeTicks = 0;
static uint64_t PMFGProbeLastScrollTicks = 0;
static uint64_t PMFGProbeLastSourceRefreshTicks = 0;
static uint64_t PMFGProbeLastDrawablePresentTicks = 0;
static uint64_t PMFGProbeLastCommandPresentTicks = 0;

static uint64_t PMFGProbeDrawableIntervalUnder10Ms = 0;
static uint64_t PMFGProbeDrawableInterval10To20Ms = 0;
static uint64_t PMFGProbeDrawableInterval20To40Ms = 0;
static uint64_t PMFGProbeDrawableInterval40MsOrMore = 0;
static uint64_t PMFGProbeCommandIntervalUnder10Ms = 0;
static uint64_t PMFGProbeCommandInterval10To20Ms = 0;
static uint64_t PMFGProbeCommandInterval20To40Ms = 0;
static uint64_t PMFGProbeCommandInterval40MsOrMore = 0;

#define PMFG_LOAD(value) __atomic_load_n(&(value), __ATOMIC_RELAXED)
#define PMFG_STORE(value, newValue) __atomic_store_n(&(value), (newValue), __ATOMIC_RELAXED)
#define PMFG_INCREMENT(value) __atomic_add_fetch(&(value), 1, __ATOMIC_RELAXED)

static void PMFGProbeWriteSnapshot(NSString *reason,
                                   uint64_t triggerTicks,
                                   uint64_t triggerWallMillis,
                                   dispatch_block_t completion);

static uint64_t PMFGProbeWallMillis(void) {
    return (uint64_t)([[NSDate date] timeIntervalSince1970] * 1000.0);
}

static double PMFGProbeTicksToSeconds(uint64_t ticks) {
    if (PMFGProbeTimebase.denom == 0) return 0;
    long double nanos = (long double)ticks * (long double)PMFGProbeTimebase.numer / (long double)PMFGProbeTimebase.denom;
    return (double)(nanos / 1000000000.0L);
}

static uint64_t PMFGProbeTicksForMilliseconds(uint64_t milliseconds) {
    if (PMFGProbeTimebase.numer == 0) return 0;
    long double nanos = (long double)milliseconds * 1000000.0L;
    return (uint64_t)(nanos * (long double)PMFGProbeTimebase.denom / (long double)PMFGProbeTimebase.numer);
}

static BOOL PMFGProbeShouldRecord(void) {
    return PMFGProbeEnabled && __atomic_load_n(&PMFGProbeAppActive, __ATOMIC_ACQUIRE) != 0;
}

static BOOL PMFGProbeTryBeginRecord(void) {
    if (!PMFGProbeEnabled) return NO;
    uint64_t generation = PMFG_LOAD(PMFGProbeSessionGeneration);
    if (__atomic_load_n(&PMFGProbeAppActive, __ATOMIC_ACQUIRE) == 0) return NO;
    PMFG_INCREMENT(PMFGProbeWriters);
    if (__atomic_load_n(&PMFGProbeAppActive, __ATOMIC_ACQUIRE) != 0 &&
        generation == PMFG_LOAD(PMFGProbeSessionGeneration)) {
        return YES;
    }
    __atomic_sub_fetch(&PMFGProbeWriters, 1, __ATOMIC_RELAXED);
    return NO;
}

static void PMFGProbeEndRecord(void) {
    __atomic_sub_fetch(&PMFGProbeWriters, 1, __ATOMIC_RELEASE);
}

static void PMFGProbeCloseAndDrainSession(void) {
    __atomic_store_n(&PMFGProbeAppActive, 0, __ATOMIC_RELEASE);
    while (__atomic_load_n(&PMFGProbeWriters, __ATOMIC_ACQUIRE) != 0) sched_yield();
}

static void PMFGProbeResetCounters(void) {
    PMFG_STORE(PMFGProbeDisplayLinkCreateCount, 0);
    PMFG_STORE(PMFGProbeDisplayLinkRangeCount, 0);
    PMFG_STORE(PMFGProbeCAAnimationRangeCount, 0);
    PMFG_STORE(PMFGProbeRangeBelow120Count, 0);
    PMFG_STORE(PMFGProbeScrollOffsetCount, 0);
    PMFG_STORE(PMFGProbeScrollAnimatedCount, 0);
    PMFG_STORE(PMFGProbeScrollLayoutMovingCount, 0);
    PMFG_STORE(PMFGProbeMetalDrawablePresentCount, 0);
    PMFG_STORE(PMFGProbeMetalCommandPresentCount, 0);
    PMFG_STORE(PMFGProbeSourceRefreshCount, 0);
    PMFG_STORE(PMFGProbeLastRangeSequence, 0);
    PMFG_STORE(PMFGProbeLastRangeSource, PMFGProbeRangeSourceNone);
    PMFG_STORE(PMFGProbeLastRangeMinimumMilli, 0);
    PMFG_STORE(PMFGProbeLastRangePreferredMilli, 0);
    PMFG_STORE(PMFGProbeLastRangeMaximumMilli, 0);
    PMFG_STORE(PMFGProbeLastRangeTicks, 0);
    PMFG_STORE(PMFGProbeLastScrollTicks, 0);
    PMFG_STORE(PMFGProbeLastSourceRefreshTicks, 0);
    PMFG_STORE(PMFGProbeLastDrawablePresentTicks, 0);
    PMFG_STORE(PMFGProbeLastCommandPresentTicks, 0);
    PMFG_STORE(PMFGProbeDrawableIntervalUnder10Ms, 0);
    PMFG_STORE(PMFGProbeDrawableInterval10To20Ms, 0);
    PMFG_STORE(PMFGProbeDrawableInterval20To40Ms, 0);
    PMFG_STORE(PMFGProbeDrawableInterval40MsOrMore, 0);
    PMFG_STORE(PMFGProbeCommandIntervalUnder10Ms, 0);
    PMFG_STORE(PMFGProbeCommandInterval10To20Ms, 0);
    PMFG_STORE(PMFGProbeCommandInterval20To40Ms, 0);
    PMFG_STORE(PMFGProbeCommandInterval40MsOrMore, 0);
}

static void PMFGProbeBeginForegroundSession(void) {
    PMFGProbeCloseAndDrainSession();
    PMFGProbeResetCounters();
    PMFG_INCREMENT(PMFGProbeSessionGeneration);
    uint64_t startTicks = mach_continuous_time();
    uint64_t startWallMillis = PMFGProbeWallMillis();
    PMFG_STORE(PMFGProbeSessionStartTicks, startTicks);
    PMFG_STORE(PMFGProbeSessionStartWallMillis, startWallMillis);
    __atomic_store_n(&PMFGProbeAppActive, 1, __ATOMIC_RELEASE);
    PMFGProbeWriteSnapshot(@"foregroundStart", startTicks, startWallMillis, nil);
}

static NSString *PMFGProbeSanitizePathPart(NSString *value) {
    if (![value isKindOfClass:[NSString class]] || value.length == 0) return @"unknown";
    NSMutableString *result = [NSMutableString stringWithCapacity:MIN(value.length, (NSUInteger)48)];
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-"];
    NSUInteger limit = MIN(value.length, (NSUInteger)48);
    for (NSUInteger index = 0; index < limit; index++) {
        unichar character = [value characterAtIndex:index];
        [result appendFormat:@"%C", [allowed characterIsMember:character] ? character : (unichar)'_'];
    }
    return result.length > 0 ? result : @"unknown";
}

static uint64_t PMFGProbeStableStringHash(NSString *value) {
    const char *bytes = [value UTF8String];
    uint64_t hash = UINT64_C(1469598103934665603);
    if (!bytes) return hash;
    for (const unsigned char *cursor = (const unsigned char *)bytes; *cursor; cursor++) {
        hash ^= (uint64_t)*cursor;
        hash *= UINT64_C(1099511628211);
    }
    return hash;
}

static NSString *PMFGProbeLatestBundlePathPart(void) {
    NSString *bundle = PMFGProbeBundleID ?: @"unknown";
    return [NSString stringWithFormat:@"%@.h%016llx",
            PMFGProbeSanitizePathPart(bundle),
            (unsigned long long)PMFGProbeStableStringHash(bundle)];
}

static NSString *PMFGProbeUniqueFileName(uint64_t sessionGeneration) {
    NSString *bundle = PMFGProbeSanitizePathPart(PMFGProbeBundleID);
    NSString *build = PMFGProbeSanitizePathPart(PMFGProbeAppBuildVersion);
    return [NSString stringWithFormat:@"com.promotion120.foreground-probe.%@.%@.p%d.t%llu.s%llu.plist",
            bundle,
            build,
            getpid(),
            (unsigned long long)PMFGProbeLoadedTicks,
            (unsigned long long)sessionGeneration];
}

static NSString *PMFGProbeVisibleUniquePath(uint64_t sessionGeneration) {
    return [@"/var/mobile/Library/Preferences" stringByAppendingPathComponent:PMFGProbeUniqueFileName(sessionGeneration)];
}

static NSString *PMFGProbeVisibleLatestPath(void) {
    return [NSString stringWithFormat:@"/var/mobile/Library/Preferences/com.promotion120.foreground-probe.%@.latest.plist",
            PMFGProbeLatestBundlePathPart()];
}

static NSString *PMFGProbeFallbackLatestPath(void) {
    return [NSString stringWithFormat:@"/tmp/com.promotion120.foreground-probe.%@.latest.plist",
            PMFGProbeLatestBundlePathPart()];
}

static NSArray<NSString *> *PMFGProbeOutputPaths(uint64_t sessionGeneration) {
    NSString *visibleUnique = PMFGProbeVisibleUniquePath(sessionGeneration);
    NSMutableArray<NSString *> *paths = [NSMutableArray array];
    for (NSString *path in @[PMFGProbeVisibleLatestPath(),
                             visibleUnique,
                             PMFGProbeFallbackLatestPath()]) {
        if (path.length > 0 && ![paths containsObject:path]) [paths addObject:path];
    }
    return paths;
}

static NSArray *PMFGProbeLoadedAppImages(void) {
    NSMutableArray *matches = [NSMutableArray array];
    NSString *bundlePath = [[[NSBundle mainBundle] bundlePath] stringByStandardizingPath];
    uint32_t count = _dyld_image_count();
    for (uint32_t index = 0; index < count && matches.count < 32; index++) {
        const char *rawName = _dyld_get_image_name(index);
        if (!rawName) continue;
        NSString *path = [[NSString stringWithUTF8String:rawName] stringByStandardizingPath];
        if (bundlePath.length == 0 || ![path hasPrefix:bundlePath]) continue;
        NSString *name = [path lastPathComponent];
        if (name.length > 0 && ![matches containsObject:name]) [matches addObject:name];
    }
    return matches;
}

static NSDictionary *PMFGProbeRangeSnapshot(void) {
    for (NSUInteger attempt = 0; attempt < 3; attempt++) {
        uint64_t firstSequence = __atomic_load_n(&PMFGProbeLastRangeSequence, __ATOMIC_ACQUIRE);
        if ((firstSequence & 1) != 0) continue;
        uint32_t source = PMFG_LOAD(PMFGProbeLastRangeSource);
        int32_t minimum = PMFG_LOAD(PMFGProbeLastRangeMinimumMilli);
        int32_t preferred = PMFG_LOAD(PMFGProbeLastRangePreferredMilli);
        int32_t maximum = PMFG_LOAD(PMFGProbeLastRangeMaximumMilli);
        uint64_t ticks = PMFG_LOAD(PMFGProbeLastRangeTicks);
        uint64_t secondSequence = __atomic_load_n(&PMFGProbeLastRangeSequence, __ATOMIC_ACQUIRE);
        if (firstSequence != secondSequence || (secondSequence & 1) != 0) continue;
        NSString *sourceName = @"none";
        if (source == PMFGProbeRangeSourceDisplayLink) sourceName = @"CADisplayLink";
        if (source == PMFGProbeRangeSourceCAAnimation) sourceName = @"CAAnimation";
        return @{
            @"coherent": @YES,
            @"source": sourceName,
            @"minimum": @((double)minimum / 1000.0),
            @"preferred": @((double)preferred / 1000.0),
            @"maximum": @((double)maximum / 1000.0),
            @"monotonicSeconds": @(PMFGProbeTicksToSeconds(ticks)),
        };
    }
    return @{ @"coherent": @NO };
}

static NSDictionary *PMFGProbeBuildSnapshot(NSString *reason,
                                             uint64_t snapshotTicks,
                                             uint64_t snapshotWallMillis,
                                             uint64_t triggerTicks,
                                             uint64_t triggerWallMillis) {
    uint64_t sessionGeneration = PMFG_LOAD(PMFGProbeSessionGeneration);
    uint64_t sessionStartTicks = PMFG_LOAD(PMFGProbeSessionStartTicks);
    uint64_t snapshotSequence = PMFG_INCREMENT(PMFGProbeSnapshotSequence);
    return @{
        @"schemaVersion": @1,
        @"probeVersion": PM_SCOPEPROBE_VERSION,
        @"captureReason": reason ?: @"unknown",
        @"snapshotSequence": @(snapshotSequence),
        @"bundleID": PMFGProbeBundleID ?: @"unknown",
        @"appShortVersion": PMFGProbeAppShortVersion ?: @"unknown",
        @"appBuildVersion": PMFGProbeAppBuildVersion ?: @"unknown",
        @"displayName": PMFGProbeDisplayName ?: @"unknown",
        @"executableName": PMFGProbeExecutableName ?: @"unknown",
        @"pid": @(getpid()),
        @"processStartToken": @(PMFGProbeLoadedTicks),
        @"loadedAt": @(PMFGProbeLoadedWallTime),
        @"sessionGeneration": @(sessionGeneration),
        @"sessionStartWallMillis": @(PMFG_LOAD(PMFGProbeSessionStartWallMillis)),
        @"sessionStartMonotonicSeconds": @(PMFGProbeTicksToSeconds(sessionStartTicks)),
        @"triggerWallMillis": @(triggerWallMillis),
        @"triggerMonotonicSeconds": @(PMFGProbeTicksToSeconds(triggerTicks)),
        @"snapshotWallMillis": @(snapshotWallMillis),
        @"snapshotMonotonicSeconds": @(PMFGProbeTicksToSeconds(snapshotTicks)),
        @"sessionDurationSeconds": @(snapshotTicks >= sessionStartTicks ? PMFGProbeTicksToSeconds(snapshotTicks - sessionStartTicks) : 0),
        @"deviceSupports120Hz": @(PMDeviceSupports120Hz()),
        @"persistentSourceAlive": @(PMAppPersistentFrameRateSource != nil),
        @"forcedRange": @{ @"minimum": @120, @"preferred": @120, @"maximum": @120 },
        @"counts": @{
            @"displayLinkCreate": @(PMFG_LOAD(PMFGProbeDisplayLinkCreateCount)),
            @"displayLinkRangeSet": @(PMFG_LOAD(PMFGProbeDisplayLinkRangeCount)),
            @"caAnimationRangeSet": @(PMFG_LOAD(PMFGProbeCAAnimationRangeCount)),
            @"rangeBelow120": @(PMFG_LOAD(PMFGProbeRangeBelow120Count)),
            @"scrollSetContentOffset": @(PMFG_LOAD(PMFGProbeScrollOffsetCount)),
            @"scrollSetContentOffsetAnimated": @(PMFG_LOAD(PMFGProbeScrollAnimatedCount)),
            @"scrollLayoutMoving": @(PMFG_LOAD(PMFGProbeScrollLayoutMovingCount)),
            @"metalDrawablePresent": @(PMFG_LOAD(PMFGProbeMetalDrawablePresentCount)),
            @"metalCommandPresent": @(PMFG_LOAD(PMFGProbeMetalCommandPresentCount)),
            @"persistentSourceRefresh": @(PMFG_LOAD(PMFGProbeSourceRefreshCount)),
        },
        @"lastRequestedRange": PMFGProbeRangeSnapshot(),
        @"lastEventMonotonicSeconds": @{
            @"scroll": @(PMFGProbeTicksToSeconds(PMFG_LOAD(PMFGProbeLastScrollTicks))),
            @"sourceRefresh": @(PMFGProbeTicksToSeconds(PMFG_LOAD(PMFGProbeLastSourceRefreshTicks))),
            @"metalDrawablePresent": @(PMFGProbeTicksToSeconds(PMFG_LOAD(PMFGProbeLastDrawablePresentTicks))),
            @"metalCommandPresent": @(PMFGProbeTicksToSeconds(PMFG_LOAD(PMFGProbeLastCommandPresentTicks))),
        },
        @"metalCadenceBuckets": @{
            @"drawable": @{
                @"under10ms": @(PMFG_LOAD(PMFGProbeDrawableIntervalUnder10Ms)),
                @"10to20ms": @(PMFG_LOAD(PMFGProbeDrawableInterval10To20Ms)),
                @"20to40ms": @(PMFG_LOAD(PMFGProbeDrawableInterval20To40Ms)),
                @"40msOrMore": @(PMFG_LOAD(PMFGProbeDrawableInterval40MsOrMore)),
            },
            @"commandBuffer": @{
                @"under10ms": @(PMFG_LOAD(PMFGProbeCommandIntervalUnder10Ms)),
                @"10to20ms": @(PMFG_LOAD(PMFGProbeCommandInterval10To20Ms)),
                @"20to40ms": @(PMFG_LOAD(PMFGProbeCommandInterval20To40Ms)),
                @"40msOrMore": @(PMFG_LOAD(PMFGProbeCommandInterval40MsOrMore)),
            },
        },
        @"loadedAppImages": PMFGProbeLoadedAppImages(),
        @"primaryOutputPath": PMFGProbeVisibleLatestPath(),
        @"outputPath": PMFGProbeVisibleUniquePath(sessionGeneration),
        @"candidateOutputPaths": PMFGProbeOutputPaths(sessionGeneration),
    };
}

static NSDictionary *PMFGProbeWriteSnapshotData(NSDictionary *snapshot, NSString *path) {
    NSError *serializationError = nil;
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:snapshot
                                                               format:NSPropertyListBinaryFormat_v1_0
                                                              options:0
                                                                error:&serializationError];
    if (!data) {
        NSMutableDictionary *result = [@{ @"success": @NO } mutableCopy];
        if (serializationError) {
            result[@"errorDomain"] = serializationError.domain ?: @"";
            result[@"errorCode"] = @(serializationError.code);
            result[@"errorDescription"] = serializationError.localizedDescription ?: @"";
        }
        return result;
    }

    NSError *writeError = nil;
    BOOL success = [data writeToFile:path options:NSDataWritingAtomic error:&writeError];
    NSMutableDictionary *result = [@{ @"success": @(success) } mutableCopy];
    if (writeError) {
        result[@"errorDomain"] = writeError.domain ?: @"";
        result[@"errorCode"] = @(writeError.code);
        result[@"errorDescription"] = writeError.localizedDescription ?: @"";
    }
    return result;
}

static void PMFGProbeWriteSnapshot(NSString *reason,
                                   uint64_t triggerTicks,
                                   uint64_t triggerWallMillis,
                                   dispatch_block_t completion) {
    uint64_t snapshotTicks = mach_continuous_time();
    uint64_t snapshotWallMillis = PMFGProbeWallMillis();
    NSDictionary *snapshot = PMFGProbeBuildSnapshot(reason,
                                                     snapshotTicks,
                                                     snapshotWallMillis,
                                                     triggerTicks,
                                                     triggerWallMillis);
    dispatch_async(PMFGProbeSnapshotQueue, ^{
        NSMutableDictionary *output = [snapshot mutableCopy];
        NSString *historyPath = output[@"outputPath"];
        output[@"writeStatus"] = @"history";
        output[@"deliveryPath"] = historyPath;
        NSDictionary *historyResult = PMFGProbeWriteSnapshotData(output, historyPath);

        NSString *latestPath = PMFGProbeVisibleLatestPath();
        NSString *fallbackPath = PMFGProbeFallbackLatestPath();
        output[@"writeResults"] = @{ historyPath: historyResult };
        output[@"writeStatus"] = @"complete";
        output[@"deliveryPath"] = latestPath;
        NSDictionary *latestResult = PMFGProbeWriteSnapshotData(output, latestPath);
        if (![latestResult[@"success"] boolValue]) {
            output[@"writeResults"] = @{
                historyPath: historyResult,
                latestPath: latestResult,
            };
            output[@"writeStatus"] = @"primaryLatestFailed";
            output[@"deliveryPath"] = fallbackPath;
            NSDictionary *fallbackResult = PMFGProbeWriteSnapshotData(output, fallbackPath);
            if (![fallbackResult[@"success"] boolValue]) {
                NSLog(@"[PMForegroundProbe] snapshot write failed: %@", @{
                    @"history": historyResult,
                    @"latest": latestResult,
                    @"fallback": fallbackResult,
                });
            }
        }
        if (completion) completion();
    });
}

static void PMFGProbeFinishMarker(uint64_t token) {
    pthread_mutex_lock(&PMFGProbeMarkerMutex);
    if (PMFGProbeMarkerState == PMFGProbeMarkerQueued &&
        PMFGProbeMarkerAcceptedToken == token) {
        PMFGProbeMarkerState = PMFGProbeMarkerIdle;
    }
    pthread_mutex_unlock(&PMFGProbeMarkerMutex);
}

static void PMFGProbeMarkerCallback(CFNotificationCenterRef center,
                                    void *observer,
                                    CFStringRef name,
                                    const void *object,
                                    CFDictionaryRef userInfo) {
    (void)center;
    (void)observer;
    (void)name;
    (void)object;
    (void)userInfo;
    if (!PMFGProbeTryBeginRecord()) return;

    pthread_mutex_lock(&PMFGProbeMarkerMutex);
    if (PMFGProbeMarkerState != PMFGProbeMarkerIdle) {
        pthread_mutex_unlock(&PMFGProbeMarkerMutex);
        PMFGProbeEndRecord();
        return;
    }
    PMFGProbeMarkerAcceptedGeneration = PMFG_LOAD(PMFGProbeSessionGeneration);
    PMFGProbeMarkerAcceptedTicks = mach_continuous_time();
    PMFGProbeMarkerAcceptedWallMillis = PMFGProbeWallMillis();
    uint64_t acceptedToken = ++PMFGProbeMarkerAcceptedToken;
    PMFGProbeMarkerState = PMFGProbeMarkerPublished;
    pthread_mutex_unlock(&PMFGProbeMarkerMutex);
    PMFGProbeEndRecord();

    dispatch_async(dispatch_get_main_queue(), ^{
        uint64_t acceptedGeneration = 0;
        uint64_t acceptedTicks = 0;
        uint64_t acceptedWallMillis = 0;
        BOOL claimed = NO;
        pthread_mutex_lock(&PMFGProbeMarkerMutex);
        if (PMFGProbeMarkerState == PMFGProbeMarkerPublished &&
            PMFGProbeMarkerAcceptedToken == acceptedToken) {
            PMFGProbeMarkerState = PMFGProbeMarkerQueued;
            acceptedGeneration = PMFGProbeMarkerAcceptedGeneration;
            acceptedTicks = PMFGProbeMarkerAcceptedTicks;
            acceptedWallMillis = PMFGProbeMarkerAcceptedWallMillis;
            claimed = YES;
        }
        pthread_mutex_unlock(&PMFGProbeMarkerMutex);
        if (!claimed) return;

        if (PMFGProbeShouldRecord() && acceptedGeneration == PMFG_LOAD(PMFGProbeSessionGeneration)) {
            PMFGProbeWriteSnapshot(@"marker.drop", acceptedTicks, acceptedWallMillis, ^{
                PMFGProbeFinishMarker(acceptedToken);
            });
            return;
        }
        PMFGProbeFinishMarker(acceptedToken);
    });
}

static void PMFGProbeRecordDisplayLinkCreate(void) {
    if (!PMFGProbeTryBeginRecord()) return;
    PMFG_INCREMENT(PMFGProbeDisplayLinkCreateCount);
    PMFGProbeEndRecord();
}

static void PMFGProbeRecordRange(PMFGProbeRangeSource source, CAFrameRateRange range) {
    if (!PMFGProbeTryBeginRecord()) return;
    if (source == PMFGProbeRangeSourceDisplayLink) PMFG_INCREMENT(PMFGProbeDisplayLinkRangeCount);
    if (source == PMFGProbeRangeSourceCAAnimation) PMFG_INCREMENT(PMFGProbeCAAnimationRangeCount);
    if ((range.preferred > 0 && range.preferred < TARGET_FPS) ||
        (range.maximum > 0 && range.maximum < TARGET_FPS)) {
        PMFG_INCREMENT(PMFGProbeRangeBelow120Count);
    }
    uint64_t sequence = __atomic_load_n(&PMFGProbeLastRangeSequence, __ATOMIC_ACQUIRE);
    if ((sequence & 1) == 0 &&
        __atomic_compare_exchange_n(&PMFGProbeLastRangeSequence,
                                    &sequence,
                                    sequence + 1,
                                    NO,
                                    __ATOMIC_ACQ_REL,
                                    __ATOMIC_RELAXED)) {
        PMFG_STORE(PMFGProbeLastRangeSource, (uint32_t)source);
        PMFG_STORE(PMFGProbeLastRangeMinimumMilli, (int32_t)(range.minimum * 1000.0f));
        PMFG_STORE(PMFGProbeLastRangePreferredMilli, (int32_t)(range.preferred * 1000.0f));
        PMFG_STORE(PMFGProbeLastRangeMaximumMilli, (int32_t)(range.maximum * 1000.0f));
        PMFG_STORE(PMFGProbeLastRangeTicks, mach_continuous_time());
        __atomic_store_n(&PMFGProbeLastRangeSequence, sequence + 2, __ATOMIC_RELEASE);
    }
    PMFGProbeEndRecord();
}

static void PMFGProbeRecordScroll(PMFGProbeScrollSource source) {
    if (!PMFGProbeTryBeginRecord()) return;
    if (source == PMFGProbeScrollSourceSetContentOffset) PMFG_INCREMENT(PMFGProbeScrollOffsetCount);
    if (source == PMFGProbeScrollSourceSetContentOffsetAnimated) PMFG_INCREMENT(PMFGProbeScrollAnimatedCount);
    if (source == PMFGProbeScrollSourceLayoutMoving) PMFG_INCREMENT(PMFGProbeScrollLayoutMovingCount);
    PMFG_STORE(PMFGProbeLastScrollTicks, mach_continuous_time());
    PMFGProbeEndRecord();
}

static uint64_t PMFGProbeAdvanceTimestamp(uint64_t *lastTicks, uint64_t nowTicks) {
    uint64_t previousTicks = __atomic_load_n(lastTicks, __ATOMIC_RELAXED);
    while (nowTicks > previousTicks) {
        if (__atomic_compare_exchange_n(lastTicks,
                                        &previousTicks,
                                        nowTicks,
                                        NO,
                                        __ATOMIC_RELAXED,
                                        __ATOMIC_RELAXED)) {
            return previousTicks;
        }
    }
    return 0;
}

static void PMFGProbeRecordCadence(uint64_t previousTicks,
                                   uint64_t nowTicks,
                                   uint64_t *under10,
                                   uint64_t *tenTo20,
                                   uint64_t *twentyTo40,
                                   uint64_t *fortyOrMore) {
    if (previousTicks == 0) return;
    uint64_t delta = nowTicks >= previousTicks ? nowTicks - previousTicks : 0;
    if (delta < PMFGProbeTenMsTicks) PMFG_INCREMENT(*under10);
    else if (delta < PMFGProbeTwentyMsTicks) PMFG_INCREMENT(*tenTo20);
    else if (delta < PMFGProbeFortyMsTicks) PMFG_INCREMENT(*twentyTo40);
    else PMFG_INCREMENT(*fortyOrMore);
}

static void PMFGProbeRecordMetal(PMFGProbeMetalSource source) {
    if (!PMFGProbeTryBeginRecord()) return;
    uint64_t now = mach_continuous_time();
    if (source == PMFGProbeMetalSourceDrawable) {
        PMFG_INCREMENT(PMFGProbeMetalDrawablePresentCount);
        uint64_t previous = PMFGProbeAdvanceTimestamp(&PMFGProbeLastDrawablePresentTicks, now);
        PMFGProbeRecordCadence(previous,
                               now,
                               &PMFGProbeDrawableIntervalUnder10Ms,
                               &PMFGProbeDrawableInterval10To20Ms,
                               &PMFGProbeDrawableInterval20To40Ms,
                               &PMFGProbeDrawableInterval40MsOrMore);
        PMFGProbeEndRecord();
        return;
    }
    PMFG_INCREMENT(PMFGProbeMetalCommandPresentCount);
    uint64_t previous = PMFGProbeAdvanceTimestamp(&PMFGProbeLastCommandPresentTicks, now);
    PMFGProbeRecordCadence(previous,
                           now,
                           &PMFGProbeCommandIntervalUnder10Ms,
                           &PMFGProbeCommandInterval10To20Ms,
                           &PMFGProbeCommandInterval20To40Ms,
                           &PMFGProbeCommandInterval40MsOrMore);
    PMFGProbeEndRecord();
}

static void PMFGProbeRecordSourceRefresh(void) {
    if (!PMFGProbeTryBeginRecord()) return;
    PMFG_INCREMENT(PMFGProbeSourceRefreshCount);
    PMFG_STORE(PMFGProbeLastSourceRefreshTicks, mach_continuous_time());
    PMFGProbeEndRecord();
}

static void PMFGProbeInit(void) {
    if (PMFGProbeEnabled || PMIsTargetProcess()) return;
    Class applicationClass = NSClassFromString(@"UIApplication");
    if (!applicationClass || ![applicationClass respondsToSelector:@selector(sharedApplication)]) return;

    UIApplication *application = [applicationClass sharedApplication];
    if (!application) return;

    NSBundle *bundle = [NSBundle mainBundle];
    NSDictionary *info = [bundle infoDictionary] ?: @{};
    PMFGProbeBundleID = [PMBundleID() copy];
    PMFGProbeAppShortVersion = [info[@"CFBundleShortVersionString"] copy] ?: @"unknown";
    PMFGProbeAppBuildVersion = [info[@"CFBundleVersion"] copy] ?: @"unknown";
    PMFGProbeDisplayName = [info[@"CFBundleDisplayName"] copy] ?: [info[@"CFBundleName"] copy] ?: @"unknown";
    PMFGProbeExecutableName = [[[NSProcessInfo processInfo] processName] copy] ?: @"unknown";
    PMFGProbeLoadedWallTime = [[NSDate date] timeIntervalSince1970];
    PMFGProbeLoadedTicks = mach_continuous_time();
    mach_timebase_info(&PMFGProbeTimebase);
    PMFGProbeTenMsTicks = PMFGProbeTicksForMilliseconds(10);
    PMFGProbeTwentyMsTicks = PMFGProbeTicksForMilliseconds(20);
    PMFGProbeFortyMsTicks = PMFGProbeTicksForMilliseconds(40);
    PMFGProbeSnapshotQueue = dispatch_queue_create("com.doimty.promotion120.foreground-probe.snapshot", DISPATCH_QUEUE_SERIAL);
    PMFGProbeEnabled = YES;

    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification
                                                      object:nil
                                                       queue:[NSOperationQueue mainQueue]
                                                  usingBlock:^(__unused NSNotification *note) {
        PMFGProbeBeginForegroundSession();
    }];
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidEnterBackgroundNotification
                                                      object:nil
                                                       queue:[NSOperationQueue mainQueue]
                                                  usingBlock:^(__unused NSNotification *note) {
        if (!PMFGProbeShouldRecord()) return;
        uint64_t generation = PMFG_LOAD(PMFGProbeSessionGeneration);
        uint64_t triggerTicks = mach_continuous_time();
        uint64_t triggerWallMillis = PMFGProbeWallMillis();
        NSString *reason = @"foregroundEnd";
        PMFGProbeCloseAndDrainSession();
        pthread_mutex_lock(&PMFGProbeMarkerMutex);
        if (PMFGProbeMarkerState == PMFGProbeMarkerPublished) {
            if (PMFGProbeMarkerAcceptedGeneration == generation) {
                reason = @"marker.drop+foregroundEnd";
                triggerTicks = PMFGProbeMarkerAcceptedTicks;
                triggerWallMillis = PMFGProbeMarkerAcceptedWallMillis;
            }
            PMFGProbeMarkerState = PMFGProbeMarkerIdle;
        }
        pthread_mutex_unlock(&PMFGProbeMarkerMutex);
        __block UIBackgroundTaskIdentifier backgroundTask = UIBackgroundTaskInvalid;
        backgroundTask = [application beginBackgroundTaskWithName:@"com.promotion120.foreground-probe.snapshot"
                                                expirationHandler:^{
            if (backgroundTask == UIBackgroundTaskInvalid) return;
            [application endBackgroundTask:backgroundTask];
            backgroundTask = UIBackgroundTaskInvalid;
        }];
        PMFGProbeWriteSnapshot(reason, triggerTicks, triggerWallMillis, ^{
            dispatch_async(dispatch_get_main_queue(), ^{
                if (backgroundTask == UIBackgroundTaskInvalid) return;
                [application endBackgroundTask:backgroundTask];
                backgroundTask = UIBackgroundTaskInvalid;
            });
        });
    }];

    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                    NULL,
                                    PMFGProbeMarkerCallback,
                                    (__bridge CFStringRef)PMFGProbeMarkerNotification,
                                    NULL,
                                    CFNotificationSuspensionBehaviorDeliverImmediately);

    if (application.applicationState == UIApplicationStateActive) {
        PMFGProbeBeginForegroundSession();
    }
}
