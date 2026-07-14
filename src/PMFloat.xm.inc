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

static void PMFloatWriteState(NSString *event, NSString *note, BOOL force) {
    // 1.0.6: telemetry plist writes fully disabled for release.
    // The PMFloat* functional path (high-refresh arming) stays active;
    // only the diagnostic writeToFile is suppressed to avoid disk I/O.
#if !PM_ENABLE_DIAGNOSTIC_PROBES
    (void)event; (void)note; (void)force;
    return;
#else
    // DISABLED in 45+nologall: prevents SIGSEGV crashes from inProcessAnimationManager
    // Re-enable for menu/edit-menu diagnosis in WeChat/Filza (limited writes only)
    // Skip if not in a target bundle
    if (!PMFloatFeatureEnabled()) return;
    // Only write for menu/edit events to keep telemetry minimal
    if (!force && ![event containsString:@"editMenu"]
        && ![event containsString:@"menu"]
        && ![event containsString:@"popover"]
        && ![event containsString:@"EditMenu"]
        && ![event containsString:@"Menu"]
        && ![event containsString:@"Popover"]) return;
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    if (!force && PMFloatLastWriteTime > 0 && (now - PMFloatLastWriteTime) < 0.20) return;
    PMFloatLastWriteTime = now;
    PMFloatLastEvent = [event copy] ?: @"";
    PMFloatLastNote = [note copy] ?: @"";
    @synchronized([NSUserDefaults class]) {
        NSMutableDictionary *root = PMFloatLoadRoot();
        root[@"state"] = @{
            @"event": PMFloatLastEvent ?: @"",
            @"note": PMFloatLastNote ?: @"",
            @"timestamp": [[NSDate date] description],
            @"lastWindowClass": PMFloatLastWindowClass ?: @"",
            @"lastRootViewControllerClass": PMFloatLastRootViewControllerClass ?: @"",
            @"lastViewClass": PMFloatLastViewClass ?: @"",
            @"lastLayerClass": PMFloatLastLayerClass ?: @"",
            @"lastAnimationClass": PMFloatLastAnimationClass ?: @"",
            @"lastAnimationKey": PMFloatLastAnimationKey ?: @"",
            @"lastDisplayLinkTargetClass": PMFloatLastDisplayLinkTargetClass ?: @"",
            @"lastPreArmReason": PMFloatLastPreArmReason ?: @"",
            @"lastFrame": PMFloatRectDict(PMFloatLastFrame),
            @"lastBounds": PMFloatRectDict(PMFloatLastBounds),
            @"lastPosition": PMFloatPointDict(PMFloatLastPosition),
            @"lastRange": @{
                @"minimum": @(PMFloatLastRangeMinimum),
                @"preferred": @(PMFloatLastRangePreferred),
                @"maximum": @(PMFloatLastRangeMaximum)
            },
            @"lastPreferredFPS": @(PMFloatLastPreferredFPS),
            @"lastFrameInterval": @(PMFloatLastFrameInterval),
            @"sourceActive": @NO,
            @"windowConfirmed": @(PMFloatWindowConfirmed),
            @"armUntil": @(PMFloatArmUntil),
            @"counts": @{
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
            },
            @"windows": PMFloatWindowSummary()
        };
        [root writeToFile:PMFloatProbeLogPath() atomically:YES];
    }
#endif // PM_ENABLE_DIAGNOSTIC_PROBES
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
#if !PM_ENABLE_DIAGNOSTIC_PROBES
    (void)event; (void)range;
    return;
#else
    if (!PMFloatFeatureEnabled()) return;
    PMFloatLastRangeMinimum = range.minimum;
    PMFloatLastRangePreferred = range.preferred;
    PMFloatLastRangeMaximum = range.maximum;
    PMFloatWriteState(event, @"range", NO);
#endif
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

static BOOL PMFloatAnyFloatingWindowVisible(void) {
    if (!PMFloatFeatureEnabled()) return NO;
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    if (PMFloatVisibleCacheAt > 0 && (now - PMFloatVisibleCacheAt) < 0.25) return PMFloatVisibleCache;
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
                if (!window.hidden && PMFloatIsFloatingWindow(window)) {
                    visible = YES;
                    PMFloatLastWindowClass = [PMClassName(window) copy];
                    PMFloatLastRootViewControllerClass = [PMClassName(window.rootViewController) copy];
                    break;
                }
            }
        }
    } @catch (__unused NSException *e) {
    }
    PMFloatVisibleCache = visible;
    PMFloatVisibleCacheAt = now;
    return visible;
}

static BOOL PMFloatShouldArmForWindow(UIWindow *window) {
    if (!PMFloatFeatureEnabled()) return NO;
    if (PMFloatIsFloatingWindow(window)) return YES;
    if (!PMFloatAnyFloatingWindowVisible()) return NO;
    NSString *windowClass = PMClassName(window);
    NSString *rootClass = @"";
    @try { rootClass = PMClassName(window.rootViewController); } @catch (__unused NSException *e) {}
    if ([windowClass containsString:@"CoverSheet"] || [windowClass containsString:@"ControlCenter"] || [rootClass containsString:@"CoverSheet"] || [rootClass containsString:@"ControlCenter"]) return NO;
    return YES;
}

static void PMFloatReleaseIfExpired(NSUInteger session);

static void PMFloatApplyDisplayFrameRateSource(NSString *event) {
    if (!PMFloatIsEligibleNow()) return;
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    // Geometry/transform bursts need sub-frame re-votes; keep a very short floor only.
    if (PMFloatLastSourceApplyAt > 0 && (now - PMFloatLastSourceApplyAt) < 0.016) return;
    @try {
        // Single-owner: no Float DynamicSource. SB re-applies Global;
        // injected apps re-apply App persistent source.
        // preferredMode pin stays on keepalive only (sparse) — do not dual-pin from float.
        if (PMIsTargetProcess()) {
            PMGlobalSBApplyForced(event ?: @"float.reapply");
        } else {
            PMAppEnsurePersistentSource();
            PMAppRefreshPersistentSource();
        }
        PMFloatLastSourceApplyAt = now;
#if PM_ENABLE_DIAGNOSTIC_PROBES
        PMFloatSourceApplyCount += 1;
        PMFloatWriteState(@"floatSource.apply", event ?: @"", NO);
#else
        (void)event;
#endif
    } @catch (__unused NSException *e) {
    }
}

static void PMFloatArm(NSString *event) {
    // Gate: only floating-view package / floating windows may arm Float.
    // Menu/alert hooks in ordinary apps must not stack a second DynamicSource on
    // top of PMAppPersistentFrameRateSource.
    if (!PMFloatFeatureEnabled() || !PMFloatAnyFloatingWindowVisible()) return;
    BOOL alreadyArmed = PMFloatIsArmed() && PMFloatWindowConfirmed;
    PMFloatWindowConfirmed = YES;
    // Resize/zoom fires geometry hooks every frame. Extend hold + re-vote only;
    // do not spin a new expire session each mutation.
    PMFloatArmUntil = CFAbsoluteTimeGetCurrent() + 4.00;
    PMFloatApplyDisplayFrameRateSource(event);
    if (alreadyArmed) return;
    PMFloatSession += 1;
    NSUInteger session = PMFloatSession;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.00 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        PMFloatReleaseIfExpired(session);
    });
}

static void PMFloatArmForWindow(UIWindow *window, NSString *event) {
    if (!PMFloatShouldArmForWindow(window)) return;
#if PM_ENABLE_DIAGNOSTIC_PROBES
    if (window) {
        PMFloatLastWindowClass = [PMClassName(window) copy];
        PMFloatLastRootViewControllerClass = [PMClassName(window.rootViewController) copy];
    }
#endif
    PMFloatArm(event);
}

static void PMFloatArmForView(UIView *view, NSString *event) {
    if (!view || !PMFloatFeatureEnabled()) return;
    UIWindow *window = nil;
    @try { window = view.window; } @catch (__unused NSException *e) {}
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
    if (PMFloatAnyFloatingWindowVisible()) PMFloatArm(event);
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
    if (!PMFloatFeatureEnabled() || !PMFloatAnyFloatingWindowVisible()) return;
#if PM_ENABLE_DIAGNOSTIC_PROBES
    PMFloatLastPreArmReason = [reason copy] ?: @"";
#endif
    BOOL alreadyArmed = PMFloatIsArmed() && PMFloatWindowConfirmed;
    PMFloatWindowConfirmed = YES;
    PMFloatArmUntil = CFAbsoluteTimeGetCurrent() + 4.00;
    PMFloatApplyDisplayFrameRateSource(reason ?: @"prearm");
#if PM_ENABLE_DIAGNOSTIC_PROBES
    PMFloatWriteState(@"floatPreArm", reason ?: @"", YES);
#endif
    if (alreadyArmed) return;
    PMFloatSession += 1;
    NSUInteger session = PMFloatSession;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.00 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        PMFloatReleaseIfExpired(session);
    });
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
        if (PMFloatAnyFloatingWindowVisible()) {
            PMFloatApplyDisplayFrameRateSource(@"float.hold");
        }
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.50 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            PMFloatReleaseIfExpired(session);
        });
        return;
    }
    // Still visible after arm window: renew instead of dropping to 60/10Hz idle floor.
    if (PMFloatAnyFloatingWindowVisible()) {
        PMFloatArm(@"float.renew");
        return;
    }
    // Single-owner model: Float never owned a DynamicSource.
    // Only clear float eligibility state. Global/App sources stay managed.
#if PM_ENABLE_DIAGNOSTIC_PROBES
    PMFloatSourceReleaseCount += 1;
#endif
    PMFloatWindowConfirmed = NO;
#if PM_ENABLE_DIAGNOSTIC_PROBES
    PMFloatWriteState(@"floatSource.release", @"expired", YES);
#endif
}
