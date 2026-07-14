#define PM_FLOAT_PROBE_TARGET_PACKAGE @"com.be-huge.floating-view"
#define PM_FLOAT_PROBE_SPRINGBOARD_LOG_PATH @"/var/mobile/Library/Preferences/com.promotion120.scopeprobe.springboard.plist"
#define PM_FLOAT_PROBE_PLUGIN_LOG_PATH @"/var/mobile/Library/Preferences/com.promotion120.scopeprobe.com.be-huge.floating-view.plist"
#define PM_FLOAT_PROBE_WECHAT_LOG_PATH @"/var/mobile/Library/Preferences/com.promotion120.scopeprobe.com.tencent.xin.plist"
#define PM_FLOAT_PROBE_FILZA_LOG_PATH @"/var/mobile/Library/Preferences/com.promotion120.scopeprobe.filza.plist"

static BOOL PMFloatWindowConfirmed = NO;
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
// Counters retained for the disabled probe schema; Float owns no DynamicSource.
static NSUInteger PMFloatSourceApplyCount = 0;
static NSUInteger PMFloatSourceReleaseCount = 0;
static NSString *PMFloatLastEvent = nil;
static NSString *PMFloatLastNote = nil;
static NSString *PMFloatLastWindowClass = nil;
static NSString *PMFloatLastRootViewControllerClass = nil;
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
static CFAbsoluteTime PMFloatLastWriteTime __attribute__((unused)) = 0;

static CFAbsoluteTime PMFloatArmUntil = 0;
static NSUInteger PMFloatSession = 0;
static BOOL PMFloatVisibleCache = NO;
static CFAbsoluteTime PMFloatVisibleCacheAt = 0;
static CFAbsoluteTime PMFloatLastSourceApplyAt = 0;
static const void *PMFloatDisplayLinkTargetClassKey = &PMFloatDisplayLinkTargetClassKey;

static BOOL PMFloatFeatureEnabled(void) {
    // Cached: bundle ID never changes within a process.
    static int cachedResult = -1;
    if (cachedResult < 0) {
        NSString *bundleID = PMBundleID();
        cachedResult = ([bundleID isEqualToString:@"com.apple.springboard"]
            || [bundleID isEqualToString:PM_FLOAT_PROBE_TARGET_PACKAGE]) ? 1 : 0;
    }
    return cachedResult == 1;
}

static NSString *PMFloatProbeLogPath(void) {
    NSString *bundleID = PMBundleID();
    if ([bundleID isEqualToString:PM_FLOAT_PROBE_TARGET_PACKAGE]) return PM_FLOAT_PROBE_PLUGIN_LOG_PATH;
    if ([bundleID isEqualToString:@"com.tencent.xin"]) return PM_FLOAT_PROBE_WECHAT_LOG_PATH;
    if ([bundleID containsString:@"filza"] || [bundleID containsString:@"Filza"]) return PM_FLOAT_PROBE_FILZA_LOG_PATH;
    return PM_FLOAT_PROBE_SPRINGBOARD_LOG_PATH;
}

static NSDictionary *PMFloatRectDict(CGRect rect) {
    return @{
        @"x": @(rect.origin.x),
        @"y": @(rect.origin.y),
        @"width": @(rect.size.width),
        @"height": @(rect.size.height)
    };
}

__attribute__((unused)) static NSDictionary *PMFloatPointDict(CGPoint point) {
    return @{
        @"x": @(point.x),
        @"y": @(point.y)
    };
}

__attribute__((unused)) static NSArray *PMFloatWindowSummary(void) {
    if (!PMFloatFeatureEnabled()) return @[];
    NSMutableArray *summary = [NSMutableArray array];
    @try {
        Class UIApplicationClass = NSClassFromString(@"UIApplication");
        if (!UIApplicationClass || ![UIApplicationClass respondsToSelector:@selector(sharedApplication)]) return summary;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        UIApplication *app = [UIApplicationClass performSelector:@selector(sharedApplication)];
#pragma clang diagnostic pop
        if (!app || ![app respondsToSelector:@selector(windows)]) return summary;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        NSArray *windows = [app performSelector:@selector(windows)];
#pragma clang diagnostic pop
        NSUInteger index = 0;
        for (UIWindow *window in windows) {
            if (index >= 16) break;
            UIViewController *root = nil;
            if ([window respondsToSelector:@selector(rootViewController)]) root = window.rootViewController;
            [summary addObject:@{
                @"index": @(index),
                @"windowClass": PMClassName(window),
                @"rootViewControllerClass": PMClassName(root),
                @"hidden": @([window isHidden]),
                @"alpha": @([window alpha]),
                @"level": @([window windowLevel]),
                @"frame": PMFloatRectDict([window frame]),
                @"bounds": PMFloatRectDict([window bounds])
            }];
            index += 1;
        }
    } @catch (__unused NSException *e) {
    }
    return summary;
}

__attribute__((unused)) static NSMutableDictionary *PMFloatLoadRoot(void) {
    NSMutableDictionary *root = [NSMutableDictionary dictionaryWithContentsOfFile:PMFloatProbeLogPath()];
    if (!root) root = [NSMutableDictionary dictionary];
    root[@"version"] = PM_SCOPEPROBE_VERSION;
    root[@"targetPackage"] = PM_FLOAT_PROBE_TARGET_PACKAGE;
    root[@"bundleID"] = PMBundleID();
    root[@"pid"] = @([[NSProcessInfo processInfo] processIdentifier]);
    root[@"lastWrite"] = [[NSDate date] description];
    return root;
}

static uint64_t PMFloatReadMotionHoldNotifyState(void) {
    static int token = -1;
    @try {
        if (token < 0) notify_register_check("com.doimty.pm120.float.motionhold", &token);
        if (token < 0) return 0;
        uint64_t st = 0;
        notify_get_state(token, &st);
        return st;
    } @catch (__unused NSException *e) {
        return 0;
    }
}

// Shared snapshot writer used by full diagnostic probes and the zoom-only probe.
static void PMFloatWriteStateSnapshot(NSString *event, NSString *note, BOOL includeWindows) {
    if (!PMFloatFeatureEnabled()) return;
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    PMFloatLastWriteTime = now;
    PMFloatLastEvent = [event copy] ?: @"";
    PMFloatLastNote = [note copy] ?: @"";
    @synchronized([NSUserDefaults class]) {
        NSMutableDictionary *root = PMFloatLoadRoot();
        NSMutableDictionary *state = [NSMutableDictionary dictionary];
        state[@"event"] = PMFloatLastEvent ?: @"";
        state[@"note"] = PMFloatLastNote ?: @"";
        state[@"timestamp"] = [[NSDate date] description];
        state[@"probeMode"] = PM_ENABLE_FLOAT_ZOOM_PROBE ? @"zoomprobe1" : @"full";
        state[@"lastWindowClass"] = PMFloatLastWindowClass ?: @"";
        state[@"lastRootViewControllerClass"] = PMFloatLastRootViewControllerClass ?: @"";
        state[@"lastViewClass"] = PMFloatLastViewClass ?: @"";
        state[@"lastLayerClass"] = PMFloatLastLayerClass ?: @"";
        state[@"lastAnimationClass"] = PMFloatLastAnimationClass ?: @"";
        state[@"lastAnimationKey"] = PMFloatLastAnimationKey ?: @"";
        state[@"lastDisplayLinkTargetClass"] = PMFloatLastDisplayLinkTargetClass ?: @"";
        state[@"lastPreArmReason"] = PMFloatLastPreArmReason ?: @"";
        state[@"lastFrame"] = PMFloatRectDict(PMFloatLastFrame);
        state[@"lastBounds"] = PMFloatRectDict(PMFloatLastBounds);
        state[@"lastPosition"] = PMFloatPointDict(PMFloatLastPosition);
        state[@"lastRange"] = @{
            @"minimum": @(PMFloatLastRangeMinimum),
            @"preferred": @(PMFloatLastRangePreferred),
            @"maximum": @(PMFloatLastRangeMaximum)
        };
        state[@"lastPreferredFPS"] = @(PMFloatLastPreferredFPS);
        state[@"lastFrameInterval"] = @(PMFloatLastFrameInterval);
        state[@"sourceActive"] = @NO;
        state[@"windowConfirmed"] = @(PMFloatWindowConfirmed);
        state[@"armUntil"] = @(PMFloatArmUntil);
        // Avoid calling later static helpers from this early writer.
        state[@"armedNow"] = @((PMFloatArmUntil > 0) && (now < PMFloatArmUntil));
        state[@"motionHoldNotify"] = @(PMFloatReadMotionHoldNotifyState());
        // floatVisible omitted here: PMFloatAnyFloatingWindowVisible is defined later.
        state[@"counts"] = @{
            @"injected": @(PMFloatProbeInjectedCount),
            @"windowSetFrame": @(PMFloatWindowSetFrameCount),
            @"windowSetBounds": @(PMFloatWindowSetBoundsCount),
            @"viewSetFrame": @(PMFloatViewSetFrameCount),
            @"viewSetBounds": @(PMFloatViewSetBoundsCount),
            @"layerSetBounds": @(PMFloatLayerSetBoundsCount),
            @"layerSetPosition": @(PMFloatLayerSetPositionCount),
            @"layerSetTransform": @(PMFloatLayerSetTransformCount),
            @"layerAddAnimation": @(PMFloatLayerAddAnimationCount),
            @"animationRangeSet": @(PMFloatAnimationRangeSetCount),
            @"displayLinkCreate": @(PMFloatDisplayLinkCreateCount),
            @"displayLinkRangeSet": @(PMFloatDisplayLinkRangeSetCount),
            @"displayLinkFPSSet": @(PMFloatDisplayLinkFPSSetCount),
            @"displayLinkFrameIntervalSet": @(PMFloatDisplayLinkFrameIntervalSetCount),
            @"preArmLowFPS": @(PMFloatPreArmLowFPSCount),
            @"preArmInProcessManager": @(PMFloatPreArmInProcessManagerCount),
            @"smallStatusBarArm": @(PMFloatSmallStatusBarArmCount),
            @"sourceCreate": @0,
            @"sourceApply": @(PMFloatSourceApplyCount),
            @"sourceRelease": @(PMFloatSourceReleaseCount)
        };
        if (includeWindows) state[@"windows"] = PMFloatWindowSummary();
        root[@"state"] = state;
        [root writeToFile:PMFloatProbeLogPath() atomically:YES];
    }
}

static void PMFloatWriteState(NSString *event, NSString *note, BOOL force) {
#if PM_ENABLE_FLOAT_ZOOM_PROBE
    // Focused zoom probe: SB + floating-view only, throttled disk writes.
    if (!PMFloatFeatureEnabled()) return;
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    if (!force && PMFloatLastWriteTime > 0 && (now - PMFloatLastWriteTime) < 0.12) return;
    @try {
        PMFloatWriteStateSnapshot(event, note, force);
    } @catch (__unused NSException *e) {}
    return;
#elif !PM_ENABLE_DIAGNOSTIC_PROBES
    (void)event; (void)note; (void)force;
    return;
#else
    // Full diagnostic path (menu/edit limited) — kept for future WeChat work.
    if (!PMFloatFeatureEnabled()) return;
    if (!force && ![event containsString:@"editMenu"]
        && ![event containsString:@"menu"]
        && ![event containsString:@"popover"]
        && ![event containsString:@"EditMenu"]
        && ![event containsString:@"Menu"]
        && ![event containsString:@"Popover"]) return;
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    if (!force && PMFloatLastWriteTime > 0 && (now - PMFloatLastWriteTime) < 0.20) return;
    @try {
        PMFloatWriteStateSnapshot(event, note, YES);
    } @catch (__unused NSException *e) {}
#endif
}

// Always-safe counter bump for float geometry hooks when full diagnostic branch is off.
static void PMFloatProbeNoteGeometry(NSString *kind, NSString *cls) {
#if PM_ENABLE_FLOAT_ZOOM_PROBE
    if (!PMFloatFeatureEnabled()) return;
    if ([kind containsString:@"UIWindow.setFrame"]) PMFloatWindowSetFrameCount += 1;
    else if ([kind containsString:@"UIWindow.setBounds"]) PMFloatWindowSetBoundsCount += 1;
    else if ([kind containsString:@"UIView.setFrame"]) PMFloatViewSetFrameCount += 1;
    else if ([kind containsString:@"UIView.setBounds"]) PMFloatViewSetBoundsCount += 1;
    else if ([kind containsString:@"CALayer.setBounds"]) PMFloatLayerSetBoundsCount += 1;
    else if ([kind containsString:@"CALayer.setPosition"]) PMFloatLayerSetPositionCount += 1;
    else if ([kind containsString:@"CALayer.setTransform"]) PMFloatLayerSetTransformCount += 1;
    else if ([kind containsString:@"CALayer.addAnimation"]) PMFloatLayerAddAnimationCount += 1;
    if (cls.length) {
        if ([kind containsString:@"UIWindow"]) PMFloatLastWindowClass = [cls copy];
        else if ([kind containsString:@"UIView"]) PMFloatLastViewClass = [cls copy];
        else if ([kind containsString:@"CALayer"]) PMFloatLastLayerClass = [cls copy];
    }
    PMFloatWriteState(kind, cls ?: @"", NO);
#else
    (void)kind; (void)cls;
#endif
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
    if (!PMFloatFeatureEnabled()) return;
    PMFloatLastRangeMinimum = range.minimum;
    PMFloatLastRangePreferred = range.preferred;
    PMFloatLastRangeMaximum = range.maximum;
    PMFloatWriteState(event, @"range", NO);
}

static BOOL PMFloatIsArmed(void) {
    return CFAbsoluteTimeGetCurrent() < PMFloatArmUntil;
}

static BOOL PMFloatIsEligibleNow(void) {
    return PMFloatWindowConfirmed && PMFloatIsArmed();
}

static BOOL PMStringHasFloatingViewMarker(NSString *name) {
    if (!name || name.length == 0) return NO;
    return [name containsString:@"floatingView."] || [name containsString:@"FVWindow"] || [name containsString:@"FVViewController"] || [name containsString:@"FVFrontConsole"];
}

static BOOL PMFloatIsFloatingWindow(UIWindow *window) {
    if (!window) return NO;
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
    // Positive hits may reuse briefly. Negative results must not stick:
    // a 0.25s false NO blocks Arm/PreArm/keepalive and causes shrink 60Hz flash.
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
                // Include alpha-weak windows; shrink may briefly hide.
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
    // Only cache positive visibility. Misses re-scan next call.
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
    if (PMStringHasFloatingViewMarker(PMClassName(view))) return YES;
    @try {
        if (PMStringHasFloatingViewMarker(PMClassName(view.nextResponder))) return YES;
    } @catch (__unused NSException *e) {}
    return NO;
}

static BOOL PMFloatShouldArmForWindow(UIWindow *window) {
    if (!PMFloatFeatureEnabled()) return NO;
    if (PMFloatIsFloatingWindow(window)) return YES;
    // nil window during detach/shrink: still arm if any float window is up or confirmed.
    if (!window) {
        return PMFloatAnyFloatingWindowVisible() || PMFloatWindowConfirmed || PMFloatIsArmed();
    }
    if (!PMFloatAnyFloatingWindowVisible() && !PMFloatWindowConfirmed && !PMFloatIsArmed()) return NO;
    NSString *windowClass = PMClassName(window);
    NSString *rootClass = @"";
    @try { rootClass = PMClassName(window.rootViewController); } @catch (__unused NSException *e) {}
    if ([windowClass containsString:@"CoverSheet"] || [windowClass containsString:@"ControlCenter"] || [rootClass containsString:@"CoverSheet"] || [rootClass containsString:@"ControlCenter"]) return NO;
    return YES;
}

static void PMFloatReleaseIfExpired(NSUInteger session);
static void PMFloatApplyDisplayFrameRateSourceEx(NSString *event, BOOL unthrottled);
static void PMFloatMotionHoldStart(void);
static void PMFloatMotionHoldStop(void);
static void PMFloatNotifySBMotionHold(BOOL active);
static void PMFloatKickKeepAliveNow(void);

// Plugin-process motion hold: whole zoom/shrink animation stays at 60 when
// only soft DynamicSource votes fire. Keep a tiny dirty DisplayLink for the
// arm window so DPPMS sees real 120 demand from the float host process.
static CADisplayLink *PMFloatMotionHoldLink = nil;
static CALayer *PMFloatMotionHoldLayer = nil;
static UIWindow *PMFloatMotionHoldWindow = nil;
static BOOL PMFloatMotionHoldActive = NO;
static int PMFloatMotionHoldNotifyToken = -1;
static int PMFloatMotionHoldSBToken = -1;

#define PM_FLOAT_MOTION_HOLD_NOTIFY "com.doimty.pm120.float.motionhold"

@interface PMFloatMotionHoldTarget : NSObject
@end
@implementation PMFloatMotionHoldTarget
- (void)pm_floatTick:(__unused CADisplayLink *)link {
    if (!PMFloatMotionHoldLayer) return;
    static BOOL toggle = NO;
    toggle = !toggle;
    PMFloatMotionHoldLayer.opacity = toggle ? 0.14f : 0.11f;
    CGFloat y = toggle ? 0.0 : 1.0;
    PMFloatMotionHoldLayer.position = CGPointMake(CGRectGetMidX(PMFloatMotionHoldLayer.bounds),
                                                 y + CGRectGetMidY(PMFloatMotionHoldLayer.bounds));
    if ([link respondsToSelector:@selector(setPreferredFrameRateRange:)]) {
        [link setPreferredFrameRateRange:PMForce120Range()];
    }
    // Plugin process: hard re-apply app persistent vote every frame of motion.
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
    // floating-view package publishes; SpringBoard reads state.
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
        // SB already has keepalive; just force it on for the motion window.
        PMFloatKickKeepAliveNow();
        return;
    }
    @try {
        if (!PMFloatMotionHoldWindow) {
            CGRect screen = [UIScreen mainScreen].bounds;
            CGFloat w = MAX(screen.size.width, screen.size.height);
            PMFloatMotionHoldWindow = [[UIWindow alloc] initWithFrame:CGRectMake(0, 0, w, 2.0)];
            PMFloatMotionHoldWindow.windowLevel = 2001.0;
            PMFloatMotionHoldWindow.userInteractionEnabled = NO;
            PMFloatMotionHoldWindow.opaque = NO;
            PMFloatMotionHoldWindow.backgroundColor = [UIColor clearColor];
            PMFloatMotionHoldWindow.hidden = NO;
            PMFloatMotionHoldLayer = [CALayer layer];
            PMFloatMotionHoldLayer.frame = CGRectMake(0, 0, w, 2.0);
            PMFloatMotionHoldLayer.backgroundColor = [UIColor colorWithWhite:1 alpha:0.12].CGColor;
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
        // Don't wait for 0.15s eval timer on shrink first frame.
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
    // Geometry first-frame path may call before eligible is fully latched.
    if (unthrottled) {
        PMFloatWindowConfirmed = YES;
        if (!PMFloatIsArmed()) PMFloatArmUntil = CFAbsoluteTimeGetCurrent() + 4.00;
    } else if (!PMFloatIsEligibleNow()) {
        return;
    }
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    // Default ~1 frame floor; shrink/zoom paths pass unthrottled.
    if (!unthrottled && PMFloatLastSourceApplyAt > 0 && (now - PMFloatLastSourceApplyAt) < 0.016) return;
    @try {
        if (PMIsTargetProcess()) {
            PMGlobalSBApplyForced(event ?: @"float.reapply");
            // Mode pin every geometry apply: animation windows stay 60 if pin is sparse.
            PMSBForceMainDisplayHighMode();
        } else {
            PMAppEnsurePersistentSource();
            if (unthrottled) PMAppRefreshPersistentSourceForced();
            else PMAppRefreshPersistentSource();
        }
        PMFloatSourceApplyCount += 1;
        PMFloatLastSourceApplyAt = now;
        PMFloatWriteState(@"floatSource.apply", event ?: @"", YES);
    } @catch (__unused NSException *e) {
    }
}

static void PMFloatArmEx(NSString *event, BOOL requireVisible, BOOL unthrottled) {
    if (!PMFloatFeatureEnabled()) return;
    if (requireVisible && !PMFloatAnyFloatingWindowVisible() && !PMFloatWindowConfirmed && !PMFloatIsArmed()) return;
    BOOL alreadyArmed = PMFloatIsArmed() && PMFloatWindowConfirmed;
    PMFloatWindowConfirmed = YES;
    PMFloatArmUntil = CFAbsoluteTimeGetCurrent() + 4.00;
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
    // Gate: only floating-view package / floating windows may arm Float.
    PMFloatArmEx(event, YES, NO);
}

static void PMFloatArmGeometry(NSString *event) {
    // Shrink/zoom: do not require fresh visible scan; unthrottled re-vote.
    PMFloatInvalidateVisibleCache();
    PMFloatArmEx(event, NO, YES);
}

static void PMFloatArmForWindow(UIWindow *window, NSString *event) {
    if (!PMFloatShouldArmForWindow(window)) return;
    if (window) {
        PMFloatLastWindowClass = [PMClassName(window) copy];
        PMFloatLastRootViewControllerClass = [PMClassName(window.rootViewController) copy];
    }
    BOOL geometry = event && ([event containsString:@"setFrame"] || [event containsString:@"setBounds"] || [event containsString:@"setTransform"] || [event containsString:@"setPosition"] || [event containsString:@"addAnimation"] || [event containsString:@"PropertyAnimator"] || [event containsString:@"statusBar"]);
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

// Post-%orig re-vote so the commit frame itself carries Forced Global / mode pin.
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

static void PMFloatPreArm(NSString *reason) {
    if (!PMFloatFeatureEnabled()) return;
    if (!PMFloatAnyFloatingWindowVisible() && !PMFloatWindowConfirmed && !PMFloatIsArmed()) return;
    PMFloatLastPreArmReason = [reason copy] ?: @"";
    // Geometry/animation prearm: unthrottled first-frame re-vote.
    PMFloatArmGeometry(reason ?: @"prearm");
    PMFloatWriteState(@"floatPreArm", reason ?: @"", YES);
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

// Forward declaration: original IMP for CADynamicFrameRateSource setHighFrameRateReasons:count:
// (fully defined later with PMInstallHooks typedefs; needed here for clean Float source release)
static void (*orig_CADynamicFrameRateSource_setHighFrameRateReasons_count)(id, SEL, const unsigned int *, NSUInteger);

static void PMFloatReleaseIfExpired(NSUInteger session) {
    if (session != PMFloatSession) return;
    if (PMFloatIsArmed()) {
        // While armed, keep re-applying source; DynamicSource votes decay under idle float UI.
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
    // Still visible after arm window: renew instead of dropping to 60/10Hz idle floor.
    if (PMFloatAnyFloatingWindowVisible() || PMFloatSBMotionHoldRequested()) {
        PMFloatArm(@"float.renew");
        return;
    }
    // Single-owner model: Float never owned a DynamicSource.
    // Only clear float eligibility state. Global/App sources stay managed.
    PMFloatMotionHoldStop();
    PMFloatSourceReleaseCount += 1;
    PMFloatWindowConfirmed = NO;
    PMFloatWriteState(@"floatSource.release", @"expired", YES);
}
