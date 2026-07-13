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
// Smart:    Only active when an injection-blocked app is in the foreground.
//           Hooked apps report their status via Darwin notify IPC.
// ─────────────────────────────────────────────────────────────────────────

// --- IPC: query frontmost app and injection status ---

static NSString *PMSBFrontmostBundleID(void) {
    @try {
        Class cls = NSClassFromString(@"SBApplicationController");
        if (!cls) return nil;
        typedef id (*PMIdGetter)(id, SEL);
        PMIdGetter getter = (PMIdGetter)objc_msgSend;
        SEL sharedSel = NSSelectorFromString(@"sharedInstance");
        if (![cls respondsToSelector:sharedSel]) return nil;
        id controller = getter((id)cls, sharedSel);
        if (!controller) return nil;
        SEL frontSel = NSSelectorFromString(@"frontmostApplication");
        if (![controller respondsToSelector:frontSel]) {
            frontSel = NSSelectorFromString(@"frontApp");
            if (![controller respondsToSelector:frontSel]) return nil;
        }
        id app = getter(controller, frontSel);
        if (!app) return nil;
        SEL bundleSel = NSSelectorFromString(@"bundleIdentifier");
        if ([app respondsToSelector:bundleSel]) return getter(app, bundleSel);
    } @catch (__unused NSException *e) {}
    return nil;
}

static NSMutableDictionary<NSString *, NSNumber *> *PMHookedTokenCache = nil;

static BOOL PMSBIsAppHooked(NSString *bundleID) {
    if (!bundleID) return NO;
    if (!PMHookedTokenCache) PMHookedTokenCache = [NSMutableDictionary new];
    int token;
    NSNumber *cached = PMHookedTokenCache[bundleID];
    if (cached) {
        token = [cached intValue];
    } else {
        char name[256];
        snprintf(name, sizeof(name), "com.doimty.pm120.hooked.%s", [bundleID UTF8String]);
        notify_register_check(name, &token);
        PMHookedTokenCache[bundleID] = @(token);
    }
    uint64_t state = 0;
    notify_get_state(token, &state);
    return state == 1;
}

// --- Keepalive state ---

static CADisplayLink *PMSBKeepAliveLink   = nil;
static UIWindow      *PMSBKeepAliveWindow = nil;
static CALayer       *PMSBDirtyLayer      = nil;
static BOOL           PMSBKeepAliveNeeded = NO;
static NSTimer       *PMSBKeepAliveEvalTimer = nil;

// Precomputed CGColors for dirty layer toggle (avoid per-frame alloc)
static CGColorRef PMSBDirtyColorA = NULL;
static CGColorRef PMSBDirtyColorB = NULL;

// --- Tick: only runs when link is unpaused ---
// v1.0.22: attach UIWindowScene + stronger dirty + CADisplay mode pin.
// 1.0.20/21 full-width 2pt/opacity 0.02 still lost to DPPMS 80Hz compromise
// when blocked-app content is dense. Bare UIWindow without scene is flaky on iOS 15+.

static CFAbsoluteTime PMSBKeepAliveHoldUntil = 0; // hysteresis after positive need
static const CGFloat PMSBKeepAliveStripH = 4.0;

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
- (void)pm_sbTick:(__unused CADisplayLink *)link {
    if (!PMSBDirtyLayer) return;
    static BOOL toggle = NO;
    static NSUInteger tick = 0;
    toggle = !toggle;
    tick += 1;

    // Dual dirty: position + color. Stronger alpha so DPPMS cannot settle at 80.
    CGFloat y = toggle ? 0.0 : 1.0;
    PMSBDirtyLayer.position = CGPointMake(CGRectGetMidX(PMSBDirtyLayer.bounds), y + CGRectGetMidY(PMSBDirtyLayer.bounds));
    PMSBDirtyLayer.backgroundColor = toggle ? PMSBDirtyColorA : PMSBDirtyColorB;
    // Force a real content commit (not just geometry) every frame.
    PMSBDirtyLayer.opacity = toggle ? 0.12f : 0.10f;

    PMSBKeepAliveApplyLinkRange();
    PMGlobalSBApplyForced(@"keepalive.tick");
    // Mode pin is heavier; ~4Hz is enough alongside per-frame vote.
    if ((tick % 30) == 0) PMSBForceMainDisplayHighMode();
}
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

// --- Evaluate: pause/unpause with hysteresis; re-assert range + window when active ---

static void PMSBKeepAliveEvaluate(void) {
    if (!PMSBKeepAliveLink) return;
    NSString *front = PMSBFrontmostBundleID();
    BOOL positive = (front != nil) && !PMSBIsAppHooked(front);
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    if (positive) {
        // Hold 2s past last positive so frontmost nil / brief transitions don't pause mid-scroll.
        PMSBKeepAliveHoldUntil = now + 2.0;
    }
    BOOL needed = positive || (now < PMSBKeepAliveHoldUntil);
    BOOL changed = (needed != PMSBKeepAliveNeeded);
    PMSBKeepAliveNeeded = needed;
    PMSBKeepAliveLink.paused = !needed;

    if (needed) {
        if (PMSBKeepAliveWindow) {
            PMSBKeepAliveAttachScene();
            PMSBKeepAliveWindow.hidden = NO;
            CGRect screen = [UIScreen mainScreen].bounds;
            CGFloat w = MAX(screen.size.width, screen.size.height);
            if (fabs(PMSBKeepAliveWindow.bounds.size.width - w) > 0.5 ||
                fabs(PMSBKeepAliveWindow.bounds.size.height - PMSBKeepAliveStripH) > 0.5) {
                PMSBKeepAliveWindow.frame = CGRectMake(0, 0, w, PMSBKeepAliveStripH);
                PMSBDirtyLayer.frame = CGRectMake(0, 0, w, PMSBKeepAliveStripH);
            }
            if (PMSBDirtyLayer && PMSBDirtyLayer.superlayer == nil) {
                [PMSBKeepAliveWindow.layer addSublayer:PMSBDirtyLayer];
            }
        }
        if (changed) {
            PMSBKeepAliveApplyLinkRange();
            PMSBForceMainDisplayHighMode();
            PMGlobalSBApplyForced(@"keepalive.activate");
        }
    }
}

// --- Install: starts paused; only burns frames for injection-blocked front apps ---

static void PMSBInstallKeepAliveLink(void) {
    if (PMSBKeepAliveLink || !PMDeviceSupports120Hz()) return;
    @try {
        CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
        CGFloat cA[4] = {0.0f, 0.0f, 0.0f, 1.0f};
        CGFloat cB[4] = {0.10f, 0.10f, 0.10f, 1.0f};
        PMSBDirtyColorA = CGColorCreate(cs, cA);
        PMSBDirtyColorB = CGColorCreate(cs, cB);
        CGColorSpaceRelease(cs);

        // Full-width strip. Higher opacity than 1.0.20 (0.02) so DPPMS cannot
        // settle the classic 80Hz compromise against dense 60Hz app content.
        CGRect screen = [UIScreen mainScreen].bounds;
        CGFloat w = MAX(screen.size.width, screen.size.height);
        PMSBKeepAliveWindow = [[UIWindow alloc] initWithFrame:CGRectMake(0, 0, w, PMSBKeepAliveStripH)];
        PMSBKeepAliveAttachScene();
        PMSBKeepAliveWindow.windowLevel              = 1000.0; // status-bar band: stays in composition
        PMSBKeepAliveWindow.hidden                   = NO;
        PMSBKeepAliveWindow.userInteractionEnabled    = NO;
        PMSBKeepAliveWindow.opaque                    = NO;
        PMSBKeepAliveWindow.backgroundColor           = [UIColor clearColor];
        PMSBKeepAliveWindow.clipsToBounds             = YES;
        PMSBKeepAliveWindow.layer.masksToBounds       = YES;

        PMSBDirtyLayer = [CALayer layer];
        PMSBDirtyLayer.frame             = CGRectMake(0, 0, w, PMSBKeepAliveStripH);
        PMSBDirtyLayer.opacity           = 0.12f;
        PMSBDirtyLayer.backgroundColor   = PMSBDirtyColorA;
        PMSBDirtyLayer.allowsGroupOpacity = NO;
        PMSBDirtyLayer.contentsScale     = [UIScreen mainScreen].scale;
        [PMSBKeepAliveWindow.layer addSublayer:PMSBDirtyLayer];

        PMSBKeepAliveTargetInstance = [[PMSBKeepAliveTarget alloc] init];
        PMSBKeepAliveLink = [CADisplayLink displayLinkWithTarget:PMSBKeepAliveTargetInstance
                                                        selector:@selector(pm_sbTick:)];
        PMSBKeepAliveLink.paused = YES;
        PMSBKeepAliveApplyLinkRange();
        [PMSBKeepAliveLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];

        PMSBKeepAliveEvalTimer = [NSTimer timerWithTimeInterval:0.15 repeats:YES block:^(__unused NSTimer *t) {
            PMSBKeepAliveEvaluate();
        }];
        [[NSRunLoop mainRunLoop] addTimer:PMSBKeepAliveEvalTimer forMode:NSRunLoopCommonModes];
        PMSBKeepAliveEvaluate();
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
            PMFPSRecordGlobalApply(@"globalSBApply", reason ?: @"unknown");
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

