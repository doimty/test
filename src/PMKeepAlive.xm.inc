static id PMGlobalSBDisplaySource = nil;
static NSUInteger PMGlobalSBCreateCount = 0;
static NSUInteger PMGlobalSBApplyCount = 0;
static BOOL PMGlobalSBEnabled = NO;
static CFAbsoluteTime PMGlobalLastApply = 0;

// ═══════════════════════════════════════════════════════════════════════════
// MARK: - Keepalive DisplayLink (prevents DPPMS downclock for blocked apps)
// ═══════════════════════════════════════════════════════════════════════════
//
// Problem:  CADynamicFrameRateSource is a "vote" DPPMS can ignore.
//           When the foreground app is injection-blocked and only produces
//           60fps content, DPPMS downclocks the display.
// Solution: A persistent CADisplayLink in SpringBoard with an empty tick.
//           The link itself is a live 120Hz consumer — DPPMS treats active
//           display links as proof of demand. The link runs immediately on
//           install and never pauses, matching the proven 1.0.9 behavior
//           (commit 74807ca).
//           No per-frame layer mutations or DynamicSource re-apply:
//           those caused CA commit contention with the app process.
// ─────────────────────────────────────────────────────────────────────────

// --- Keepalive state ---

static CADisplayLink *PMSBKeepAliveLink = nil;
static NSUInteger PMSBKeepAliveRetryCount = 0;

@interface PMSBKeepAliveTarget : NSObject
@end
@implementation PMSBKeepAliveTarget
- (void)pm_sbTick:(__unused CADisplayLink *)link {}
@end

// CADisplayLink must not depend on a local target surviving installation.
// Keep the target alive for the lifetime of the persistent link.
static PMSBKeepAliveTarget *PMSBKeepAliveTargetInstance = nil;

static void PMSBKeepAliveApplyLinkRange(void) {
    if (!PMSBKeepAliveLink) return;
    if ([PMSBKeepAliveLink respondsToSelector:@selector(setPreferredFrameRateRange:)]) {
        [PMSBKeepAliveLink setPreferredFrameRateRange:PMForce120Range()];
    } else if ([PMSBKeepAliveLink respondsToSelector:@selector(setPreferredFramesPerSecond:)]) {
        [PMSBKeepAliveLink setPreferredFramesPerSecond:TARGET_FPS];
    }
}

// --- Install: always-on DisplayLink, no pause, no evaluation, no dirty layer ---

static void PMSBInstallKeepAliveLink(void) {
    if (PMSBKeepAliveLink || !PMDeviceSupports120Hz()) return;
    @try {
        PMSBKeepAliveTargetInstance = [[PMSBKeepAliveTarget alloc] init];
        PMSBKeepAliveLink = [CADisplayLink displayLinkWithTarget:PMSBKeepAliveTargetInstance
                                                        selector:@selector(pm_sbTick:)];
        PMSBKeepAliveApplyLinkRange();
        [PMSBKeepAliveLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    } @catch (__unused NSException *e) {}
}


static void PMGlobalSBApplyForced(NSString *reason) {
    // Single SB owner, no throttle. Used by scroll and float re-apply paths.
    if (!PMIsTargetProcess() || !PMDeviceSupports120Hz()) return;
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    @try {
        if (!PMGlobalSBDisplaySource) {
            Class SC = NSClassFromString(@"CADynamicFrameRateSource");
            id display = PMMainCADisplay();
            if (SC && display) {
                id allocd = [SC alloc];
                SEL initS = NSSelectorFromString(@"initWithDisplay:");
                if ([allocd respondsToSelector:initS]) {
                    typedef id (*PMInitFn)(id, SEL, id);
                    PMInitFn f = (PMInitFn)objc_msgSend;
                    PMGlobalSBDisplaySource = f(allocd, initS, display);
                    PMGlobalSBCreateCount += 1;
                }
            }
        }
        if (PMGlobalSBDisplaySource) {
            PMSetHighFrameRateReasonDirect(PMGlobalSBDisplaySource);
            PMSetFrameRateRangeDirect(PMGlobalSBDisplaySource);
            PMGlobalSBApplyCount += 1;
            PMGlobalLastApply = now;
        }
    } @catch (NSException *exc) { }
}

static void PMSBScheduleKeepAliveRetry(void) {
    if (PMSBKeepAliveLink || PMSBKeepAliveRetryCount >= 8) return;
    PMSBKeepAliveRetryCount += 1;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.50 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (PMSBKeepAliveLink) return;
        PMSBInstallKeepAliveLink();
        if (!PMSBKeepAliveLink) PMSBScheduleKeepAliveRetry();
    });
}

static void PMGlobalSBApply(NSString *reason) {
    // Throttled path for banner/float/scroll hooks. Keepalive uses Forced.
    if (!PMIsTargetProcess() || !PMDeviceSupports120Hz()) return;
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    if (PMGlobalLastApply > 0 && (now - PMGlobalLastApply) < 0.20) return;
    PMGlobalSBApplyForced(reason);
}

static void PMGlobalSBSetup(void) {
    if (!PMGlobalSBEnabled) {
        PMGlobalSBEnabled = YES;
        PMGlobalSBApply(@"setup");
    }
    PMSBInstallKeepAliveLink();
    if (!PMSBKeepAliveLink) PMSBScheduleKeepAliveRetry();
}