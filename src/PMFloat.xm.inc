// Float window 120Hz support.
// Scope: SpringBoard + com.be-huge.floating-view only.
// No disk probes. Single-owner: SB Global / App persistent; Float does not own DynamicSource.

#define PM_FLOAT_HOST_PACKAGE @"com.be-huge.floating-view"

static BOOL PMFloatWindowConfirmed = NO;
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
            || [bundleID isEqualToString:PM_FLOAT_HOST_PACKAGE]) ? 1 : 0;
    }
    return cachedResult == 1;
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
        // preferredMode pin stays on keepalive only (sparse) — do not dual-pin from float.
        if (PMIsTargetProcess()) {
            PMGlobalSBApplyForced(event ?: @"float.reapply");
        } else {
            PMAppEnsurePersistentSource();
            PMAppRefreshPersistentSource();
        }
        PMFloatLastSourceApplyAt = now;
    } @catch (__unused NSException *e) {
    }
}

static void PMFloatArm(NSString *event) {
    // Gate: only floating-view package / floating windows may arm Float.
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
    BOOL alreadyArmed = PMFloatIsArmed() && PMFloatWindowConfirmed;
    PMFloatWindowConfirmed = YES;
    PMFloatArmUntil = CFAbsoluteTimeGetCurrent() + 4.00;
    PMFloatApplyDisplayFrameRateSource(reason ?: @"prearm");
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
    PMFloatWindowConfirmed = NO;
}
