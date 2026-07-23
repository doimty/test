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
// Solution: A persistent CADisplayLink in SpringBoard that toggles a tiny
//           offscreen dirty layer every frame, producing real render commits
//           that DPPMS treats as proof of 120Hz demand.
//           Always-on: the link starts running immediately and never pauses.
//           This matches the proven 1.0.9 behavior (commit 74807ca).
//           Smart evaluation (paused/unpaused) was unreliable because
//           Darwin notify IPC state can be lost on app relaunch, and the
//           evaluation timer misses transitions.
// ─────────────────────────────────────────────────────────────────────────

// --- Keepalive state ---

static CADisplayLink *PMSBKeepAliveLink   = nil;
static UIWindow      *PMSBKeepAliveWindow = nil;
static CALayer       *PMSBDirtyLayer      = nil;

// Precomputed CGColors for dirty layer toggle (avoid per-frame alloc)
static CGColorRef PMSBDirtyColorA = NULL;
static CGColorRef PMSBDirtyColorB = NULL;

// --- Tick: runs every frame (link is always on) ---
// v1.0.22: attach UIWindowScene + stronger dirty + CADisplay mode pin.
// 1.0.20/21 full-width 2pt/opacity 0.02 still lost to DPPMS 80Hz compromise
// when blocked-app content is dense. Bare UIWindow without scene is flaky on iOS 15+.

// Pinned host: offscreen 1x1 (no visible top strip). Keepalive demand =
// DisplayLink range + Global DynamicSource + sparse preferredMode pin.
// Only valid on 24-float baseline (do not recombine with 25/26 float thrash).
static const CGFloat PMSBKeepAliveStripH = 1.0;
static const CGFloat PMSBKeepAliveOffX = -20.0;
static const CGFloat PMSBKeepAliveOffY = -20.0;

static void PMSBKeepAliveAttachScene(void) {
    if (!PMSBKeepAliveWindow) return;
    @try {
        // iOS 13+: unattached UIWindow may never commit; pin to any live SB scene.
        if (![PMSBKeepAliveWindow respondsToSelector:@selector(setWindowScene:)]) return;
        id currentScene = nil;
        if ([PMSBKeepAliveWindow respondsToSelector:@selector(windowScene)]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            currentScene = [PMSBKeepAliveWindow performSelector:@selector(windowScene)];
#pragma clang diagnostic pop
        }
        if (currentScene) return;

        Class UIApplicationClass = NSClassFromString(@"UIApplication");
        if (!UIApplicationClass || ![UIApplicationClass respondsToSelector:@selector(sharedApplication)]) return;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        UIApplication *app = [UIApplicationClass performSelector:@selector(sharedApplication)];
#pragma clang diagnostic pop
        if (!app) return;

        id scene = nil;
        if ([app respondsToSelector:@selector(connectedScenes)]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            NSSet *scenes = [app performSelector:@selector(connectedScenes)];
#pragma clang diagnostic pop
            for (id s in scenes) {
                NSString *cls = PMClassName(s);
                if ([cls containsString:@"UIWindowScene"]) { scene = s; break; }
            }
        }
        if (!scene && [app respondsToSelector:@selector(windows)]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            NSArray *windows = [app performSelector:@selector(windows)];
#pragma clang diagnostic pop
            for (UIWindow *w in windows) {
                if (w == PMSBKeepAliveWindow) continue;
                if ([w respondsToSelector:@selector(windowScene)]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                    scene = [w performSelector:@selector(windowScene)];
#pragma clang diagnostic pop
                    if (scene) break;
                }
            }
        }
        if (scene) {
            typedef void (*PMSetSceneFn)(id, SEL, id);
            PMSetSceneFn setScene = (PMSetSceneFn)objc_msgSend;
            setScene(PMSBKeepAliveWindow, @selector(setWindowScene:), scene);
        }
    } @catch (__unused NSException *e) {}
}

static void PMSBForceMainDisplayHighMode(void) {
    // Best-effort pin preferredMode to highest refreshRate (>=119). Silent no-op if private API differs.
    @try {
        id display = PMMainCADisplay();
        if (!display) return;
        NSArray *modes = [display valueForKey:@"availableModes"];
        if (![modes isKindOfClass:[NSArray class]] || modes.count == 0) return;
        id best = nil;
        double bestRate = 0;
        for (id mode in modes) {
            double rate = [[mode valueForKey:@"refreshRate"] doubleValue];
            if (rate > bestRate) { bestRate = rate; best = mode; }
        }
        if (!best || bestRate < 119.0) return;
        id current = nil;
        @try { current = [display valueForKey:@"preferredMode"]; } @catch (__unused NSException *e) {}
        if (current == best) return;
        @try { [display setValue:best forKey:@"preferredMode"]; } @catch (__unused NSException *e) {}
    } @catch (__unused NSException *e) {}
}

@interface PMSBKeepAliveTarget : NSObject
@end
@implementation PMSBKeepAliveTarget
// Empty tick: matches proven 1.0.9 behavior (commit 74807ca).
// The DisplayLink itself is the 120Hz consumer that DPPMS sees.
// Per-frame dirty layer mutations + DynamicSource re-apply +
// mode pin caused CA commit contention with the app process.
- (void)pm_sbTick:(__unused CADisplayLink *)link {}
@end

static PMSBKeepAliveTarget *PMSBKeepAliveTargetInstance = nil;

static void PMSBKeepAliveApplyLinkRange(void) {
    if (!PMSBKeepAliveLink) return;
    if ([PMSBKeepAliveLink respondsToSelector:@selector(setPreferredFrameRateRange:)]) {
        [PMSBKeepAliveLink setPreferredFrameRateRange:PMForce120Range()];
    } else if ([PMSBKeepAliveLink respondsToSelector:@selector(setPreferredFramesPerSecond:)]) {
        [PMSBKeepAliveLink setPreferredFramesPerSecond:TARGET_FPS];
    }
}

// --- Install: always-on DisplayLink (no pause/evaluation) ---

static void PMSBInstallKeepAliveLink(void) {
    if (PMSBKeepAliveLink || !PMDeviceSupports120Hz()) return;
    @try {
        CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
        CGFloat cA[4] = {0.0f, 0.0f, 0.0f, 1.0f};
        CGFloat cB[4] = {0.10f, 0.10f, 0.10f, 1.0f};
        PMSBDirtyColorA = CGColorCreate(cs, cA);
        PMSBDirtyColorB = CGColorCreate(cs, cB);
        CGColorSpaceRelease(cs);

        // Offscreen 1x1 host (no visible top strip). Demand = DisplayLink +
        // Global DynamicSource + sparse mode pin on 24-float baseline.
        PMSBKeepAliveWindow = [[UIWindow alloc] initWithFrame:CGRectMake(PMSBKeepAliveOffX, PMSBKeepAliveOffY, PMSBKeepAliveStripH, PMSBKeepAliveStripH)];
        PMSBKeepAliveAttachScene();
        PMSBKeepAliveWindow.windowLevel              = -9999.0; // intentionally out of visible stack
        PMSBKeepAliveWindow.hidden                   = NO;
        PMSBKeepAliveWindow.userInteractionEnabled    = NO;
        PMSBKeepAliveWindow.opaque                    = NO;
        PMSBKeepAliveWindow.backgroundColor           = [UIColor clearColor];
        PMSBKeepAliveWindow.clipsToBounds             = YES;
        PMSBKeepAliveWindow.layer.masksToBounds       = YES;

        PMSBDirtyLayer = [CALayer layer];
        PMSBDirtyLayer.frame             = CGRectMake(0, 0, PMSBKeepAliveStripH, PMSBKeepAliveStripH);
        PMSBDirtyLayer.opacity           = 0.12f;
        PMSBDirtyLayer.backgroundColor   = PMSBDirtyColorA;
        PMSBDirtyLayer.allowsGroupOpacity = NO;
        PMSBDirtyLayer.contentsScale     = [UIScreen mainScreen].scale;
        [PMSBKeepAliveWindow.layer addSublayer:PMSBDirtyLayer];

        PMSBKeepAliveTargetInstance = [[PMSBKeepAliveTarget alloc] init];
        PMSBKeepAliveLink = [CADisplayLink displayLinkWithTarget:PMSBKeepAliveTargetInstance
                                                        selector:@selector(pm_sbTick:)];
        // Always-on: matches proven 1.0.9 behavior (commit 74807ca).
        // No pause/evaluation — the link runs from install until the process dies.
        PMSBKeepAliveApplyLinkRange();
        [PMSBKeepAliveLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    } @catch (__unused NSException *e) {}
}


static void PMGlobalSBApplyForced(NSString *reason) {
    // Single SB owner, no throttle. Used by keepalive tick (scroll fight).
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

static void PMGlobalSBApply(NSString *reason) {
    // Throttled path for banner/float/scroll hooks. Keepalive uses Forced.
    if (!PMIsTargetProcess() || !PMDeviceSupports120Hz()) return;
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    if (PMGlobalLastApply > 0 && (now - PMGlobalLastApply) < 0.20) return;
    PMGlobalSBApplyForced(reason);
}

static void PMGlobalSBSetup(void) {
    if (PMGlobalSBEnabled) return;
    PMGlobalSBEnabled = YES;
    PMGlobalSBApply(@"setup");
    PMSBInstallKeepAliveLink();
}