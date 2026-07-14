// Float window / menu 120Hz support.
// Scope: SpringBoard + com.be-huge.floating-view only.
// No disk probes. Plugin publishes Darwin motion-hold; SB owns dirty keepalive.

#define PM_FLOAT_HOST_PACKAGE @"com.be-huge.floating-view"
#define PM_FLOAT_MOTION_HOLD_NOTIFY "com.doimty.pm120.float.motionhold"

static BOOL PMFloatWindowConfirmed = NO;
static CFAbsoluteTime PMFloatArmUntil = 0;
static NSUInteger PMFloatSession = 0;
static BOOL PMFloatVisibleCache = NO;
static CFAbsoluteTime PMFloatVisibleCacheAt = 0;
static CFAbsoluteTime PMFloatLastSourceApplyAt = 0;

// Retained for optional last-class notes in arm helpers (no I/O).
static NSString *PMFloatLastWindowClass = nil;
static NSString *PMFloatLastRootViewControllerClass = nil;

static CADisplayLink *PMFloatMotionHoldLink = nil;
static CALayer *PMFloatMotionHoldLayer = nil;
static UIWindow *PMFloatMotionHoldWindow = nil;
static BOOL PMFloatMotionHoldActive = NO;
static int PMFloatMotionHoldNotifyToken = -1;
static int PMFloatMotionHoldSBToken = -1;

// Compat names used by older hook call sites (no probe I/O).
static NSUInteger PMFloatProbeInjectedCount = 0;
static NSUInteger PMFloatWindowSetFrameCount = 0;
static NSUInteger PMFloatWindowSetBoundsCount = 0;
static NSUInteger PMFloatViewSetFrameCount = 0;
static NSUInteger PMFloatViewSetBoundsCount = 0;
static NSUInteger PMFloatLayerSetBoundsCount = 0;
static NSUInteger PMFloatLayerSetPositionCount = 0;
static NSUInteger PMFloatLayerSetTransformCount = 0;
static NSUInteger PMFloatLayerAddAnimationCount = 0;
static NSUInteger PMFloatAnimationRangeSetCount = 0;
static NSUInteger PMFloatDisplayLinkCreateCount = 0;
static NSUInteger PMFloatDisplayLinkRangeSetCount = 0;
static NSUInteger PMFloatDisplayLinkFPSSetCount = 0;
static NSUInteger PMFloatDisplayLinkFrameIntervalSetCount = 0;
static NSUInteger PMFloatPreArmLowFPSCount = 0;
static NSUInteger PMFloatPreArmInProcessManagerCount = 0;
static NSUInteger PMFloatSmallStatusBarArmCount = 0;
static NSUInteger PMFloatSourceApplyCount = 0;
static NSUInteger PMFloatSourceReleaseCount = 0;
static NSString *PMFloatLastViewClass = nil;
static NSString *PMFloatLastLayerClass = nil;
static NSString *PMFloatLastAnimationClass = nil;
static NSString *PMFloatLastAnimationKey = nil;
static NSString *PMFloatLastDisplayLinkTargetClass = nil;
static NSString *PMFloatLastPreArmReason = nil;
static double PMFloatLastRangeMinimum = 0;
static double PMFloatLastRangePreferred = 0;
static double PMFloatLastRangeMaximum = 0;
static NSInteger PMFloatLastPreferredFPS = 0;
static NSInteger PMFloatLastFrameInterval = 0;
static CGRect PMFloatLastFrame = {{0, 0}, {0, 0}};
static CGRect PMFloatLastBounds = {{0, 0}, {0, 0}};
static CGPoint PMFloatLastPosition = {0, 0};
static const void *PMFloatDisplayLinkTargetClassKey = &PMFloatDisplayLinkTargetClassKey;

// Legacy alias so older includes keep compiling if they reference the probe package name.
#ifndef PM_FLOAT_PROBE_TARGET_PACKAGE
#define PM_FLOAT_PROBE_TARGET_PACKAGE PM_FLOAT_HOST_PACKAGE
#endif

static BOOL PMFloatFeatureEnabled(void) {
    static int cachedResult = -1;
    if (cachedResult < 0) {
        NSString *bundleID = PMBundleID();
        cachedResult = ([bundleID isEqualToString:@"com.apple.springboard"]
            || [bundleID isEqualToString:PM_FLOAT_HOST_PACKAGE]) ? 1 : 0;
    }
    return cachedResult == 1;
}

static void PMFloatWriteState(NSString *event, NSString *note, BOOL force) {
    (void)event; (void)note; (void)force;
}

static void PMFloatProbeNoteGeometry(NSString *kind, NSString *cls) {
    (void)kind; (void)cls;
}

static void PMFloatCaptureWindowInfoForView(UIView *view) {
    if (!PMFloatFeatureEnabled() || !view) return;
    @try {
        UIWindow *window = view.window;
        if (window) {
            PMFloatLastWindowClass = [PMClassName(window) copy];
            PMFloatLastRootViewControllerClass = [PMClassName(window.rootViewController) copy];
        }
    } @catch (__unused NSException *e) {
    }
}

static void PMFloatRecordRange(NSString *event, CAFrameRateRange range) {
    (void)event;
    if (!PMFloatFeatureEnabled()) return;
    PMFloatLastRangeMinimum = range.minimum;
    PMFloatLastRangePreferred = range.preferred;
    PMFloatLastRangeMaximum = range.maximum;
}

static BOOL PMFloatIsArmed(void) {
    return CFAbsoluteTimeGetCurrent() < PMFloatArmUntil;
}

static BOOL PMFloatIsEligibleNow(void) {
    return PMFloatWindowConfirmed && PMFloatIsArmed();
}

static BOOL PMStringHasFloatingViewMarker(NSString *name) {
    if (!name || name.length == 0) return NO;
    return [name containsString:@"floatingView."]
        || [name containsString:@"FVWindow"]
        || [name containsString:@"FVViewController"]
        || [name containsString:@"FVFrontConsole"];
}

static BOOL PMFloatIsPluginProcess(void) {
    static int cached = -1;
    if (cached < 0) {
        cached = [PMBundleID() isEqualToString:PM_FLOAT_HOST_PACKAGE] ? 1 : 0;
    }
    return cached == 1;
}

static BOOL PMFloatIsFloatingWindow(UIWindow *window) {
    if (!window) return NO;
    // Host process: class markers often miss real windows. Treat any window as float-eligible.
    if (PMFloatIsPluginProcess()) return YES;
    NSString *windowClass = PMClassName(window);
    NSString *rootClass = @"";
    @try { rootClass = PMClassName(window.rootViewController); } @catch (__unused NSException *e) {}
    return PMStringHasFloatingViewMarker(windowClass) || PMStringHasFloatingViewMarker(rootClass);
}

static void PMFloatInvalidateVisibleCache(void) {
    PMFloatVisibleCacheAt = 0;
    PMFloatVisibleCache = NO;
}

static BOOL PMFloatAnyFloatingWindowVisible(void) {
    if (!PMFloatFeatureEnabled()) return NO;
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    if (PMFloatVisibleCache && PMFloatVisibleCacheAt > 0 && (now - PMFloatVisibleCacheAt) < 0.05) {
        return YES;
    }
    BOOL visible = NO;
    @try {
        Class UIApplicationClass = NSClassFromString(@"UIApplication");
        if (UIApplicationClass && [UIApplicationClass respondsToSelector:@selector(sharedApplication)]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            UIApplication *app = [UIApplicationClass performSelector:@selector(sharedApplication)];
#pragma clang diagnostic pop
            NSArray *windows = nil;
            if (app && [app respondsToSelector:@selector(windows)]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                windows = [app performSelector:@selector(windows)];
#pragma clang diagnostic pop
            }
            for (UIWindow *window in windows) {
                if (PMFloatIsFloatingWindow(window) && (!window.hidden || window.alpha > 0.01)) {
                    visible = YES;
                    PMFloatLastWindowClass = [PMClassName(window) copy];
                    PMFloatLastRootViewControllerClass = [PMClassName(window.rootViewController) copy];
                    break;
                }
            }
        }
    } @catch (__unused NSException *e) {
    }
    if (visible) {
        PMFloatVisibleCache = YES;
        PMFloatVisibleCacheAt = now;
    } else {
        PMFloatVisibleCache = NO;
        PMFloatVisibleCacheAt = 0;
    }
    return visible;
}

static BOOL PMFloatViewLooksFloating(UIView *view) {
    if (!view) return NO;
    if (PMFloatIsPluginProcess()) return YES;
    if (PMStringHasFloatingViewMarker(PMClassName(view))) return YES;
    @try {
        if (PMStringHasFloatingViewMarker(PMClassName(view.nextResponder))) return YES;
    } @catch (__unused NSException *e) {}
    return NO;
}

static BOOL PMFloatShouldArmForWindow(UIWindow *window) {
    if (!PMFloatFeatureEnabled()) return NO;
    if (PMFloatIsFloatingWindow(window)) return YES;
    if (!window) {
        return PMFloatAnyFloatingWindowVisible() || PMFloatWindowConfirmed || PMFloatIsArmed();
    }
    if (!PMFloatAnyFloatingWindowVisible() && !PMFloatWindowConfirmed && !PMFloatIsArmed()) return NO;
    NSString *windowClass = PMClassName(window);
    NSString *rootClass = @"";
    @try { rootClass = PMClassName(window.rootViewController); } @catch (__unused NSException *e) {}
    if ([windowClass containsString:@"CoverSheet"] || [windowClass containsString:@"ControlCenter"]
        || [rootClass containsString:@"CoverSheet"] || [rootClass containsString:@"ControlCenter"]) {
        return NO;
    }
    return YES;
}

static void PMFloatReleaseIfExpired(NSUInteger session);
static void PMFloatApplyDisplayFrameRateSourceEx(NSString *event, BOOL unthrottled);
static void PMFloatMotionHoldStart(void);
static void PMFloatMotionHoldStop(void);
static void PMFloatNotifySBMotionHold(BOOL active);
static void PMFloatKickKeepAliveNow(void);

@interface PMFloatMotionHoldTarget : NSObject
@end
@implementation PMFloatMotionHoldTarget
- (void)pm_floatTick:(__unused CADisplayLink *)link {
    if (!PMFloatMotionHoldLayer) return;
    static BOOL toggle = NO;
    toggle = !toggle;
    // Near-invisible dirty flip (was alpha 0.11–0.14, showed as a top strip).
    PMFloatMotionHoldLayer.opacity = toggle ? 0.02f : 0.01f;
    CGFloat y = toggle ? 0.0 : 1.0;
    PMFloatMotionHoldLayer.position = CGPointMake(CGRectGetMidX(PMFloatMotionHoldLayer.bounds),
                                                 y + CGRectGetMidY(PMFloatMotionHoldLayer.bounds));
    if ([link respondsToSelector:@selector(setPreferredFrameRateRange:)]) {
        [link setPreferredFrameRateRange:PMForce120Range()];
    }
    if (!PMIsTargetProcess()) {
        PMAppEnsurePersistentSource();
        PMAppRefreshPersistentSourceForced();
    } else {
        PMGlobalSBApplyForced(@"float.motion.tick");
        PMSBForceMainDisplayHighMode();
    }
}
@end
static PMFloatMotionHoldTarget *PMFloatMotionHoldTargetInstance = nil;

static void PMFloatNotifySBMotionHold(BOOL active) {
    if (PMIsTargetProcess()) return;
    @try {
        if (PMFloatMotionHoldNotifyToken < 0) {
            notify_register_check(PM_FLOAT_MOTION_HOLD_NOTIFY, &PMFloatMotionHoldNotifyToken);
        }
        if (PMFloatMotionHoldNotifyToken >= 0) {
            notify_set_state(PMFloatMotionHoldNotifyToken, active ? 1 : 0);
            notify_post(PM_FLOAT_MOTION_HOLD_NOTIFY);
        }
    } @catch (__unused NSException *e) {}
}

static BOOL PMFloatSBMotionHoldRequested(void) {
    if (!PMIsTargetProcess()) return NO;
    @try {
        if (PMFloatMotionHoldSBToken < 0) {
            notify_register_check(PM_FLOAT_MOTION_HOLD_NOTIFY, &PMFloatMotionHoldSBToken);
        }
        if (PMFloatMotionHoldSBToken < 0) return NO;
        uint64_t state = 0;
        notify_get_state(PMFloatMotionHoldSBToken, &state);
        return state == 1;
    } @catch (__unused NSException *e) {
        return NO;
    }
}

static void PMFloatMotionHoldStart(void) {
    if (!PMFloatFeatureEnabled() || !PMDeviceSupports120Hz()) return;
    PMFloatMotionHoldActive = YES;
    PMFloatNotifySBMotionHold(YES);
    if (PMIsTargetProcess()) {
        PMFloatKickKeepAliveNow();
        return;
    }
    @try {
        if (!PMFloatMotionHoldWindow) {
            CGRect screen = [UIScreen mainScreen].bounds;
            CGFloat w = MAX(screen.size.width, screen.size.height);
            PMFloatMotionHoldWindow = [[UIWindow alloc] initWithFrame:CGRectMake(0, 0, w, 1.0)];
            PMFloatMotionHoldWindow.windowLevel = 2001.0;
            PMFloatMotionHoldWindow.userInteractionEnabled = NO;
            PMFloatMotionHoldWindow.opaque = NO;
            PMFloatMotionHoldWindow.backgroundColor = [UIColor clearColor];
            PMFloatMotionHoldWindow.hidden = NO;
            PMFloatMotionHoldLayer = [CALayer layer];
            PMFloatMotionHoldLayer.frame = CGRectMake(0, 0, w, 1.0);
            PMFloatMotionHoldLayer.backgroundColor = [UIColor colorWithWhite:0 alpha:1].CGColor;
            PMFloatMotionHoldLayer.opacity = 0.02f;
            [PMFloatMotionHoldWindow.layer addSublayer:PMFloatMotionHoldLayer];
        } else {
            PMFloatMotionHoldWindow.hidden = NO;
        }
        if (!PMFloatMotionHoldTargetInstance) {
            PMFloatMotionHoldTargetInstance = [[PMFloatMotionHoldTarget alloc] init];
        }
        if (!PMFloatMotionHoldLink) {
            PMFloatMotionHoldLink = [CADisplayLink displayLinkWithTarget:PMFloatMotionHoldTargetInstance
                                                               selector:@selector(pm_floatTick:)];
            if ([PMFloatMotionHoldLink respondsToSelector:@selector(setPreferredFrameRateRange:)]) {
                [PMFloatMotionHoldLink setPreferredFrameRateRange:PMForce120Range()];
            } else if ([PMFloatMotionHoldLink respondsToSelector:@selector(setPreferredFramesPerSecond:)]) {
                [PMFloatMotionHoldLink setPreferredFramesPerSecond:TARGET_FPS];
            }
            [PMFloatMotionHoldLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
        }
        PMFloatMotionHoldLink.paused = NO;
        PMAppEnsurePersistentSource();
        PMAppRefreshPersistentSourceForced();
    } @catch (__unused NSException *e) {}
}

static void PMFloatMotionHoldStop(void) {
    PMFloatMotionHoldActive = NO;
    PMFloatNotifySBMotionHold(NO);
    @try {
        if (PMFloatMotionHoldLink) PMFloatMotionHoldLink.paused = YES;
        if (PMFloatMotionHoldWindow) PMFloatMotionHoldWindow.hidden = YES;
    } @catch (__unused NSException *e) {}
}

static void PMFloatKickKeepAliveNow(void) {
    if (!PMIsTargetProcess()) return;
    @try {
        PMSBKeepAliveEvaluate();
        if (PMSBKeepAliveLink) {
            PMSBKeepAliveLink.paused = NO;
            PMSBKeepAliveNeeded = YES;
            PMSBKeepAliveHoldUntil = CFAbsoluteTimeGetCurrent() + 2.0;
            PMSBKeepAliveApplyLinkRange();
        }
        PMSBForceMainDisplayHighMode();
        PMGlobalSBApplyForced(@"float.kick.keepalive");
    } @catch (__unused NSException *e) {}
}

static void PMFloatApplyDisplayFrameRateSourceEx(NSString *event, BOOL unthrottled) {
    if (!PMFloatIsEligibleNow() && !unthrottled) return;
    if (unthrottled) {
        PMFloatWindowConfirmed = YES;
        if (!PMFloatIsArmed()) PMFloatArmUntil = CFAbsoluteTimeGetCurrent() + 4.00;
    } else if (!PMFloatIsEligibleNow()) {
        return;
    }
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    if (!unthrottled && PMFloatLastSourceApplyAt > 0 && (now - PMFloatLastSourceApplyAt) < 0.016) return;
    @try {
        if (PMIsTargetProcess()) {
            PMGlobalSBApplyForced(event ?: @"float.reapply");
            PMSBForceMainDisplayHighMode();
        } else {
            PMAppEnsurePersistentSource();
            if (unthrottled) PMAppRefreshPersistentSourceForced();
            else PMAppRefreshPersistentSource();
        }
        PMFloatSourceApplyCount += 1;
        PMFloatLastSourceApplyAt = now;
    } @catch (__unused NSException *e) {
    }
}

static void PMFloatArmEx(NSString *event, BOOL requireVisible, BOOL unthrottled) {
    if (!PMFloatFeatureEnabled()) return;
    if (requireVisible && !PMFloatIsPluginProcess()
        && !PMFloatAnyFloatingWindowVisible() && !PMFloatWindowConfirmed && !PMFloatIsArmed()) return;
    BOOL alreadyArmed = PMFloatIsArmed() && PMFloatWindowConfirmed;
    PMFloatWindowConfirmed = YES;
    PMFloatArmUntil = CFAbsoluteTimeGetCurrent() + (unthrottled ? 6.00 : 4.00);
    PMFloatApplyDisplayFrameRateSourceEx(event, unthrottled);
    if (unthrottled || !alreadyArmed) {
        PMFloatMotionHoldStart();
        if (PMIsTargetProcess()) PMFloatKickKeepAliveNow();
    }
    if (alreadyArmed) return;
    PMFloatSession += 1;
    NSUInteger session = PMFloatSession;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.00 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        PMFloatReleaseIfExpired(session);
    });
}

static void PMFloatArm(NSString *event) {
    PMFloatArmEx(event, YES, NO);
}

static void PMFloatArmGeometry(NSString *event) {
    PMFloatInvalidateVisibleCache();
    PMFloatArmEx(event, NO, YES);
}

// PreArm is ArmGeometry (single entry). Kept as a name for hook call sites.
static void PMFloatPreArm(NSString *reason) {
    if (!PMFloatFeatureEnabled()) return;
    if (!PMFloatIsPluginProcess()
        && !PMFloatAnyFloatingWindowVisible() && !PMFloatWindowConfirmed && !PMFloatIsArmed()) return;
    PMFloatLastPreArmReason = [reason copy] ?: @"";
    PMFloatArmGeometry(reason ?: @"prearm");
}

static void PMFloatArmForWindow(UIWindow *window, NSString *event) {
    if (!PMFloatShouldArmForWindow(window)) return;
    if (window) {
        PMFloatLastWindowClass = [PMClassName(window) copy];
        PMFloatLastRootViewControllerClass = [PMClassName(window.rootViewController) copy];
    }
    BOOL geometry = event && ([event containsString:@"setFrame"]
        || [event containsString:@"setBounds"]
        || [event containsString:@"setTransform"]
        || [event containsString:@"setPosition"]
        || [event containsString:@"addAnimation"]
        || [event containsString:@"PropertyAnimator"]
        || [event containsString:@"statusBar"]);
    if (geometry) PMFloatArmGeometry(event);
    else PMFloatArm(event);
}

static void PMFloatArmForView(UIView *view, NSString *event) {
    if (!view || !PMFloatFeatureEnabled()) return;
    UIWindow *window = nil;
    @try { window = view.window; } @catch (__unused NSException *e) {}
    if (!window && (PMFloatViewLooksFloating(view) || PMFloatWindowConfirmed || PMFloatIsArmed() || PMFloatAnyFloatingWindowVisible())) {
        PMFloatArmGeometry(event ?: @"UIView.nilWindow");
        return;
    }
    PMFloatArmForWindow(window, event);
}

static void PMFloatArmForLayer(CALayer *layer, NSString *event) {
    if (!layer || !PMFloatFeatureEnabled()) return;
    @try {
        id delegate = layer.delegate;
        if ([delegate isKindOfClass:[UIView class]]) {
            PMFloatArmForView((UIView *)delegate, event);
            return;
        }
    } @catch (__unused NSException *e) {
    }
    if (PMFloatAnyFloatingWindowVisible() || PMFloatWindowConfirmed || PMFloatIsArmed()) {
        PMFloatArmGeometry(event ?: @"CALayer");
    }
}

static void PMFloatReassertAfterGeometry(NSString *event) {
    if (!PMFloatFeatureEnabled()) return;
    if (!(PMFloatWindowConfirmed || PMFloatIsArmed() || PMFloatAnyFloatingWindowVisible())) return;
    PMFloatWindowConfirmed = YES;
    if (!PMFloatIsArmed()) PMFloatArmUntil = CFAbsoluteTimeGetCurrent() + 4.00;
    PMFloatApplyDisplayFrameRateSourceEx(event ?: @"geometry.post", YES);
    PMFloatKickKeepAliveNow();
}

static BOOL PMFloatRectLooksLikeCollapsedCapsule(CGRect rect) {
    CGFloat w = rect.size.width;
    CGFloat h = rect.size.height;
    return (w >= 40 && w <= 180 && h >= 30 && h <= 120);
}

static BOOL PMFloatWindowLooksLikeStatusShrinkWindow(UIWindow *window) {
    if (!window) return NO;
    NSString *windowClass = PMClassName(window);
    if ([windowClass containsString:@"StatusBar"] || [windowClass isEqualToString:@"UIStatusBarWindow"]) return YES;
    return NO;
}

static NSString *PMFloatDisplayLinkTargetClass(id link) {
    NSString *targetClass = nil;
    @try {
        targetClass = objc_getAssociatedObject(link, PMFloatDisplayLinkTargetClassKey);
    } @catch (__unused NSException *e) {
    }
    return targetClass ?: @"";
}

static BOOL PMFloatTargetIsInProcessAnimationManager(NSString *targetClass) {
    return targetClass && [targetClass containsString:@"UIViewInProcessAnimationManager"];
}

static void (*orig_CADynamicFrameRateSource_setHighFrameRateReasons_count)(id, SEL, const unsigned int *, NSUInteger);

static void PMFloatReleaseIfExpired(NSUInteger session) {
    if (session != PMFloatSession) return;
    if (PMFloatIsArmed()) {
        if (PMFloatAnyFloatingWindowVisible() || PMFloatMotionHoldActive || PMFloatSBMotionHoldRequested()) {
            PMFloatApplyDisplayFrameRateSourceEx(@"float.hold", YES);
            if (PMIsTargetProcess()) PMFloatKickKeepAliveNow();
            else PMFloatMotionHoldStart();
        }
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.50 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            PMFloatReleaseIfExpired(session);
        });
        return;
    }
    if (PMFloatAnyFloatingWindowVisible() || PMFloatSBMotionHoldRequested()) {
        PMFloatArm(@"float.renew");
        return;
    }
    PMFloatMotionHoldStop();
    PMFloatSourceReleaseCount += 1;
    PMFloatWindowConfirmed = NO;
}