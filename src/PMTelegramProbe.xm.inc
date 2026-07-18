// Telegram chat probe: logs CADisplayLink, CADynamicFrameRateSource, UIScrollView,
// and Metal rendering activity to a plist for offline analysis.
// Only active in ph.telegra.Telegraph process (Telegram).

#import <objc/runtime.h>

static NSString * const PMTGProbePath = @"/var/mobile/Library/Preferences/com.promotion120.tgprobe.plist";
static NSMutableDictionary *PMTGProbeState = nil;
static NSMutableDictionary *PMTGProbeCounts = nil;
static dispatch_queue_t PMTGProbeQueue = nil;
static CFAbsoluteTime PMTGProbeLastWrite = 0;
static const CFTimeInterval PMTGProbeWriteInterval = 2.0;
static BOOL PMTGProbeEnabled = NO;

static BOOL PMIsTelegramProcess(void) {
    static BOOL checked = NO, isTG = NO;
    if (!checked) {
        NSString *bid = [[NSBundle mainBundle] bundleIdentifier];
        isTG = [bid isEqualToString:@"ph.telegra.Telegraph"];
        checked = YES;
    }
    return isTG;
}

static void PMTGProbeInit(void) {
    if (!PMIsTelegramProcess()) return;
    PMTGProbeEnabled = YES;
    PMTGProbeQueue = dispatch_queue_create("pm120.tgprobe", DISPATCH_QUEUE_SERIAL);
    PMTGProbeCounts = [NSMutableDictionary new];
    PMTGProbeState = [@{
        @"bundleID": [[NSBundle mainBundle] bundleIdentifier] ?: @"unknown",
        @"version": PM_SCOPEPROBE_VERSION ?: @"unknown",
        @"probeMode": @"tgchat1",
        @"pid": @(getpid()),
    } mutableCopy];
}

static void PMTGProbeIncrement(NSString *key) {
    if (!PMTGProbeEnabled) return;
    dispatch_async(PMTGProbeQueue, ^{
        NSNumber *cur = PMTGProbeCounts[key];
        PMTGProbeCounts[key] = @(cur.integerValue + 1);
    });
}

static void PMTGProbeSet(NSString *key, id value) {
    if (!PMTGProbeEnabled || !key || !value) return;
    dispatch_async(PMTGProbeQueue, ^{
        PMTGProbeState[key] = value;
    });
}

static void PMTGProbeWrite(void) {
    if (!PMTGProbeEnabled) return;
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    if ((now - PMTGProbeLastWrite) < PMTGProbeWriteInterval) return;
    PMTGProbeLastWrite = now;
    dispatch_async(PMTGProbeQueue, ^{
        NSMutableDictionary *out = [PMTGProbeState mutableCopy];
        out[@"counts"] = [PMTGProbeCounts copy];
        out[@"timestamp"] = [[NSDate date] description];
        out[@"persistentSourceAlive"] = @(PMAppPersistentFrameRateSource != nil ? YES : NO);
        [out writeToFile:PMTGProbePath atomically:YES];
    });
}

// Record CADisplayLink creation with target class
static void PMTGProbeDisplayLinkCreated(id target, CADisplayLink *link) {
    if (!PMTGProbeEnabled) return;
    NSString *cls = PMClassName(target);
    PMTGProbeIncrement(@"displayLinkCreate");
    PMTGProbeSet(@"lastDisplayLinkTarget", cls ?: @"nil");
    PMTGProbeIncrement([NSString stringWithFormat:@"dlCreate.%@", cls ?: @"unknown"]);
    PMTGProbeWrite();
}

// Record setPreferredFrameRateRange with actual values
static void PMTGProbeRangeSet(CAFrameRateRange original, NSString *source) {
    if (!PMTGProbeEnabled) return;
    PMTGProbeIncrement(@"rangeSet");
    PMTGProbeSet(@"lastRangeSource", source ?: @"unknown");
    PMTGProbeSet(@"lastOriginalRange", ([NSString stringWithFormat:@"min=%.0f pref=%.0f max=%.0f", original.minimum, original.preferred, original.maximum]));
    // Track if any code requests < 120
    if (original.preferred > 0 && original.preferred < 120) {
        PMTGProbeIncrement(@"rangeSetBelow120");
        PMTGProbeSet(@"lastBelow120Range", ([NSString stringWithFormat:@"min=%.0f pref=%.0f max=%.0f", original.minimum, original.preferred, original.maximum]));
    }
    PMTGProbeWrite();
}

// Record scroll events
static void PMTGProbeScroll(NSString *event, UIScrollView *sv) {
    if (!PMTGProbeEnabled) return;
    PMTGProbeIncrement([NSString stringWithFormat:@"scroll.%@", event]);
    NSString *svClass = NSStringFromClass([sv class]);
    PMTGProbeSet(@"lastScrollViewClass", svClass);
    PMTGProbeSet(@"lastScrollDragging", @(sv.dragging));
    PMTGProbeSet(@"lastScrollDecelerating", @(sv.decelerating));
    PMTGProbeWrite();
}

// Record Metal present calls
static void PMTGProbeMetalPresent(NSString *event) {
    if (!PMTGProbeEnabled) return;
    PMTGProbeIncrement([NSString stringWithFormat:@"metal.%@", event]);
    PMTGProbeWrite();
}

// Record persistent source refresh
static void PMTGProbeSourceRefresh(NSString *reason) {
    if (!PMTGProbeEnabled) return;
    PMTGProbeIncrement(@"sourceRefresh");
    PMTGProbeSet(@"lastSourceRefreshReason", reason);
    PMTGProbeWrite();
}
