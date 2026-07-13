// ============================================================
// scopeprobe1: WeChat album/image low-refresh telemetry
// Only records class names, counters, and frame-rate parameters.
// It intentionally does not record chat text, contacts, image paths, URLs, or screenshots.
// ============================================================
#define PM_SCOPEPROBE_VERSION @"1.0.5"
#define PM_ENABLE_DIAGNOSTIC_PROBES 0
#define PM_WECHAT_PROBE_LOG_PATH @"/var/mobile/Library/Preferences/com.promotion120.scopeprobe.com.tencent.xin.plist"

static NSUInteger PMProbeInjectedCount = 0;
static NSUInteger PMProbeUIScreenMaxQueryCount = 0;
static NSUInteger PMProbeDisplayLinkCreateCount = 0;
static NSUInteger PMProbeDisplayLinkRangeSetCount = 0;
static NSUInteger PMProbeDisplayLinkFPSSetCount = 0;
static NSUInteger PMProbeDisplayLinkFrameIntervalSetCount = 0;
static NSUInteger PMProbeAnimationRangeSetCount = 0;
static NSUInteger PMProbeLayerAddAnimationCount = 0;
static NSUInteger PMProbeViewDidAppearCount = 0;
static NSUInteger PMProbePresentViewControllerCount = 0;
static NSUInteger PMProbePushViewControllerCount = 0;
static NSUInteger PMProbeCollectionReloadCount = 0;
static NSUInteger PMProbeCollectionLayoutCount = 0;
static NSUInteger PMProbeTableReloadCount = 0;
static NSUInteger PMProbeTableLayoutCount = 0;
static NSUInteger PMProbeWindowSetFrameCount = 0;
static NSUInteger PMProbeWindowSetBoundsCount = 0;
static NSUInteger PMProbeViewSetFrameCount = 0;
static NSUInteger PMProbeViewSetBoundsCount = 0;
static NSUInteger PMProbeLayerSetBoundsCount = 0;
static NSUInteger PMProbeLayerSetPositionCount = 0;
static NSUInteger PMProbeLayerSetTransformCount = 0;
static NSUInteger PMProbeScrollSetContentOffsetCount = 0;
static NSUInteger PMProbePropertyAnimatorStartCount = 0;
static NSUInteger PMProbeMetalDrawablePresentCount = 0;
static NSUInteger PMProbeCommandBufferPresentCount = 0;
static NSString *PMProbeLastEvent = nil;
static NSString *PMProbeLastNote = nil;
static NSString *PMProbeLastViewControllerClass = nil;
static NSString *PMProbeLastViewClass = nil;
static NSString *PMProbeLastPresentedViewControllerClass = nil;
static NSString *PMProbeLastNavigationPushedClass = nil;
static NSString *PMProbeLastWindowClass = nil;
static NSString *PMProbeLastRootViewControllerClass = nil;
static NSString *PMProbeLastDisplayLinkTargetClass = nil;
static NSString *PMProbeLastLayerClass = nil;
static NSString *PMProbeLastAnimationClass = nil;
static NSString *PMProbeLastAnimationKey = nil;
static NSString *PMProbeLastCollectionClass = nil;
static NSString *PMProbeLastTableClass = nil;
static double PMProbeLastRangeMinimum = 0;
static double PMProbeLastRangePreferred = 0;
static double PMProbeLastRangeMaximum = 0;
static NSInteger PMProbeLastPreferredFPS = 0;
static NSInteger PMProbeLastFrameInterval = 0;
static CGRect PMProbeLastFrame = {{0, 0}, {0, 0}};
static CGRect PMProbeLastBounds = {{0, 0}, {0, 0}};
static CGPoint PMProbeLastPosition = {0, 0};
static CGPoint PMProbeLastContentOffset = {0, 0};
static CGSize PMProbeLastContentSize = {0, 0};
static CFAbsoluteTime PMProbeLastWriteTime = 0;

static BOOL PMProbeIsWeChat(void) {
#if !PM_ENABLE_DIAGNOSTIC_PROBES
    return NO;
#else
    return [PMBundleID() isEqualToString:@"com.tencent.xin"];
#endif
}

static NSDictionary *PMProbeRectDict(CGRect rect) {
    return @{
        @"x": @(rect.origin.x),
        @"y": @(rect.origin.y),
        @"width": @(rect.size.width),
        @"height": @(rect.size.height)
    };
}

static NSDictionary *PMProbePointDict(CGPoint point) {
    return @{
        @"x": @(point.x),
        @"y": @(point.y)
    };
}

static NSDictionary *PMProbeSizeDict(CGSize size) {
    return @{
        @"width": @(size.width),
        @"height": @(size.height)
    };
}

static NSArray *PMProbeWindowSummary(void) {
    if (!PMProbeIsWeChat()) return @[];
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
            if (index >= 8) break;
            UIViewController *root = nil;
            if ([window respondsToSelector:@selector(rootViewController)]) root = window.rootViewController;
            [summary addObject:@{
                @"index": @(index),
                @"windowClass": PMClassName(window),
                @"rootViewControllerClass": PMClassName(root),
                @"hidden": @([window isHidden]),
                @"alpha": @([window alpha]),
                @"level": @([window windowLevel])
            }];
            index += 1;
        }
    } @catch (__unused NSException *e) {
    }
    return summary;
}

__attribute__((unused)) static void PMProbeCaptureCurrentWindowInfo(id viewOrController) {
    if (!PMProbeIsWeChat()) return;
    @try {
        UIView *view = nil;
        if ([viewOrController isKindOfClass:[UIView class]]) {
            view = (UIView *)viewOrController;
        } else if ([viewOrController respondsToSelector:@selector(view)]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            view = [viewOrController performSelector:@selector(view)];
#pragma clang diagnostic pop
        }
        UIWindow *window = view.window;
        if (window) {
            PMProbeLastWindowClass = [PMClassName(window) copy];
            PMProbeLastRootViewControllerClass = [PMClassName(window.rootViewController) copy];
        }
    } @catch (__unused NSException *e) {
    }
}

static NSMutableDictionary *PMProbeLoadRoot(void) {
    NSMutableDictionary *root = [NSMutableDictionary dictionaryWithContentsOfFile:PM_WECHAT_PROBE_LOG_PATH];
    if (!root) root = [NSMutableDictionary dictionary];
    root[@"version"] = PM_SCOPEPROBE_VERSION;
    root[@"bundleID"] = PMBundleID();
    root[@"pid"] = @([[NSProcessInfo processInfo] processIdentifier]);
    root[@"lastWrite"] = [[NSDate date] description];
    return root;
}

static NSDictionary *PMProbeEventSnapshot(NSString *event, NSString *note) {
    return @{
        @"timestamp": [[NSDate date] description],
        @"event": event ?: @"",
        @"note": note ?: @"",
        @"lastViewControllerClass": PMProbeLastViewControllerClass ?: @"",
        @"lastViewClass": PMProbeLastViewClass ?: @"",
        @"lastPresentedViewControllerClass": PMProbeLastPresentedViewControllerClass ?: @"",
        @"lastNavigationPushedClass": PMProbeLastNavigationPushedClass ?: @"",
        @"lastWindowClass": PMProbeLastWindowClass ?: @"",
        @"lastRootViewControllerClass": PMProbeLastRootViewControllerClass ?: @"",
        @"lastDisplayLinkTargetClass": PMProbeLastDisplayLinkTargetClass ?: @"",
        @"lastLayerClass": PMProbeLastLayerClass ?: @"",
        @"lastAnimationClass": PMProbeLastAnimationClass ?: @"",
        @"lastAnimationKey": PMProbeLastAnimationKey ?: @"",
        @"lastCollectionClass": PMProbeLastCollectionClass ?: @"",
        @"lastTableClass": PMProbeLastTableClass ?: @"",
        @"lastFrame": PMProbeRectDict(PMProbeLastFrame),
        @"lastBounds": PMProbeRectDict(PMProbeLastBounds),
        @"lastPosition": PMProbePointDict(PMProbeLastPosition),
        @"lastContentOffset": PMProbePointDict(PMProbeLastContentOffset),
        @"lastContentSize": PMProbeSizeDict(PMProbeLastContentSize),
        @"lastRange": @{
            @"minimum": @(PMProbeLastRangeMinimum),
            @"preferred": @(PMProbeLastRangePreferred),
            @"maximum": @(PMProbeLastRangeMaximum)
        },
        @"lastPreferredFPS": @(PMProbeLastPreferredFPS),
        @"lastFrameInterval": @(PMProbeLastFrameInterval)
    };
}

// === FPS Probe: safe numeric-only telemetry (47+fpsprobe2) ===
// Safe: NO object enumeration, NO window/rootVC/collection retention.
// Writes only: strings, numbers, timestamps, counts. Throttled 0.5s minimum.
// 47+: records original incoming range vs our override to identify external low-FPS sources.

static NSString *PMFPSLastEvent = nil;
static NSString *PMFPSLastReason = nil;
static NSString *PMFPSLastSceneName = nil;
static double PMFPSLastMin = 0;
static double PMFPSLastPreferred = 0;
static double PMFPSLastMax = 0;
static double PMFPSLastOrigMin = 0;
static double PMFPSLastOrigPreferred = 0;
static double PMFPSLastOrigMax = 0;
static NSUInteger PMFPSWriteCount = 0;
static CFAbsoluteTime PMFPSLastWrite = 0;
static NSUInteger PMFPSLowFPSDropCount = 0;
static NSUInteger PMFPSRangeSetCount = 0;
static NSUInteger PMFPSSourceApplyCount = 0;
static NSUInteger PMFPSGlobalApplyCount = 0;
static NSUInteger PMFPSOverriddenCount = 0;
static NSInteger PMFPSLastOrigFPS = -1;
static NSInteger PMFPSLastAppliedFPS = -1;
static NSInteger PMFPSLastOrigInterval = -1;
static NSInteger PMFPSLastAppliedInterval = -1;
static NSUInteger PMFPSFPSSetCount = 0;
static NSUInteger PMFPSFrameIntervalSetCount = 0;
static double PMActualLastDeltaMs = 0;
static double PMActualMaxDeltaMs = 0;
static double PMActualLastDurationMs = 0;
static NSUInteger PMActualTickCount = 0;
static NSUInteger PMActualLowTickCount = 0;
static NSUInteger PMActualVeryLowTickCount = 0;
static NSUInteger PMActualIgnoredLongGapCount = 0;
static double PMActualLastLowDeltaMs = 0;
static double PMActualLastLowDurationMs = 0;
static double PMActualMaxFilteredDeltaMs = 0;
static CFTimeInterval PMActualLastTimestamp = 0;
static CFTimeInterval PMActualLastLowTimestamp = 0;
static CADisplayLink *PMActualProbeLink = nil;
static id PMActualProbeTargetInstance = nil;

// === Jank Probe: safe numeric/string-only context for actual low ticks (52+jankprobe1) ===
// Safe: no object enumeration, no object values in dictionaries; only class names, counters, geometry, runloop mode.
static NSString *PMJankLastRunLoopMode = nil;
static NSString *PMJankLastLowRunLoopMode = nil;
static NSString *PMJankLastActivity = nil;
static NSString *PMJankLastActivityClass = nil;
static NSString *PMJankLastScrollClass = nil;
static NSString *PMJankLastListClass = nil;
static NSString *PMJankLastViewClass = nil;
static NSString *PMJankLastLayerClass = nil;
static NSString *PMJankLastAnimationClass = nil;
static NSString *PMJankLastAnimationKey = nil;
static NSString *PMJankLastDisplayLinkTargetClass = nil;
static CFAbsoluteTime PMJankLastActivityAt = 0;
static CFAbsoluteTime PMJankLastClassUpdateAt = 0;
static NSUInteger PMJankActivityCount = 0;
static NSUInteger PMJankScrollOffsetCount = 0;
static NSUInteger PMJankListLayoutCount = 0;
static NSUInteger PMJankListReloadCount = 0;
static NSUInteger PMJankViewFrameCount = 0;
static NSUInteger PMJankViewBoundsCount = 0;
static NSUInteger PMJankLayerAnimationCount = 0;
static NSUInteger PMJankLayerMutationCount = 0;
static NSUInteger PMJankPropertyAnimatorCount = 0;
static NSUInteger PMJankDisplayLinkCreateCount = 0;
static CGPoint PMJankLastContentOffset = {0, 0};
static CGSize PMJankLastContentSize = {0, 0};
static CGRect PMJankLastViewFrame = {{0, 0}, {0, 0}};
static CGRect PMJankLastViewBounds = {{0, 0}, {0, 0}};
static BOOL PMJankLastScrollDragging = NO;
static BOOL PMJankLastScrollTracking = NO;
static BOOL PMJankLastScrollDecelerating = NO;

static NSString *PMJankCopyMainRunLoopModeName(void) {
    @try {
        CFStringRef mode = CFRunLoopCopyCurrentMode(CFRunLoopGetMain());
        if (mode) return [((__bridge_transfer NSString *)mode) copy] ?: @"";
    } @catch (__unused NSException *e) {
    }
    return @"";
}

static double PMJankLastActivityAgeMs(void) {
    if (PMJankLastActivityAt <= 0) return -1.0;
    return (CFAbsoluteTimeGetCurrent() - PMJankLastActivityAt) * 1000.0;
}

static BOOL PMJankClassLooksRelevant(NSString *className) {
    if (!className || className.length == 0) return NO;
    return [className containsString:@"NC"] || [className containsString:@"Notification"] ||
           [className containsString:@"SB"] || [className containsString:@"Banner"] ||
           [className containsString:@"CoverSheet"] || [className containsString:@"Scroll"] ||
           [className containsString:@"List"] || [className containsString:@"Collection"] ||
           [className containsString:@"Table"] || [className containsString:@"floatingView"] ||
           [className containsString:@"FV"];
}

static void PMJankRecordActivity(NSString *event, NSString *className, BOOL forceClass) {
#if !PM_ENABLE_DIAGNOSTIC_PROBES
    return;
#endif
    if (!PMIsTargetProcess()) return;
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    PMJankActivityCount += 1;
    PMJankLastActivityAt = now;
    PMJankLastActivity = [event copy] ?: @"";
    if (forceClass || PMJankClassLooksRelevant(className) || PMJankLastClassUpdateAt <= 0 || (now - PMJankLastClassUpdateAt) > 0.10) {
        PMJankLastActivityClass = [className copy] ?: @"";
        PMJankLastClassUpdateAt = now;
    }
}

static void PMJankRecordScrollView(UIScrollView *scrollView, CGPoint offset) {
#if !PM_ENABLE_DIAGNOSTIC_PROBES
    return;
#endif
    if (!PMIsTargetProcess() || !scrollView) return;
    @try {
        PMJankScrollOffsetCount += 1;
        NSString *className = PMClassName(scrollView);
        PMJankLastScrollClass = [className copy] ?: @"";
        PMJankLastContentOffset = offset;
        PMJankLastContentSize = scrollView.contentSize;
        PMJankLastScrollDragging = scrollView.dragging;
        PMJankLastScrollTracking = scrollView.tracking;
        PMJankLastScrollDecelerating = scrollView.decelerating;
        PMJankRecordActivity(@"UIScrollView.setContentOffset", className, YES);
    } @catch (__unused NSException *e) {}
}

static void PMJankRecordListView(UIView *view, NSString *event, BOOL isReload) {
#if !PM_ENABLE_DIAGNOSTIC_PROBES
    return;
#endif
    if (!PMIsTargetProcess() || !view) return;
    @try {
        if (isReload) PMJankListReloadCount += 1; else PMJankListLayoutCount += 1;
        NSString *className = PMClassName(view);
        PMJankLastListClass = [className copy] ?: @"";
        PMJankRecordActivity(event ?: @"list", className, YES);
    } @catch (__unused NSException *e) {}
}

static void PMJankRecordViewMutation(UIView *view, NSString *event, CGRect rect, BOOL isBounds) {
#if !PM_ENABLE_DIAGNOSTIC_PROBES
    return;
#endif
    if (!PMIsTargetProcess() || !view) return;
    @try {
        if (isBounds) {
            PMJankViewBoundsCount += 1;
            PMJankLastViewBounds = rect;
        } else {
            PMJankViewFrameCount += 1;
            PMJankLastViewFrame = rect;
        }
        NSString *className = PMClassName(view);
        if (PMJankClassLooksRelevant(className)) PMJankLastViewClass = [className copy] ?: @"";
        PMJankRecordActivity(event ?: @"view", className, NO);
    } @catch (__unused NSException *e) {}
}

static void PMJankRecordLayerAnimation(CALayer *layer, CAAnimation *animation, NSString *key) {
#if !PM_ENABLE_DIAGNOSTIC_PROBES
    return;
#endif
    if (!PMIsTargetProcess()) return;
    @try {
        PMJankLayerAnimationCount += 1;
        NSString *layerClass = PMClassName(layer);
        PMJankLastLayerClass = [layerClass copy] ?: @"";
        PMJankLastAnimationClass = [PMClassName(animation) copy] ?: @"";
        PMJankLastAnimationKey = [key copy] ?: @"";
        PMJankRecordActivity(@"CALayer.addAnimation", layerClass, YES);
    } @catch (__unused NSException *e) {}
}

static void PMJankRecordLayerMutation(CALayer *layer, NSString *event) {
#if !PM_ENABLE_DIAGNOSTIC_PROBES
    return;
#endif
    if (!PMIsTargetProcess()) return;
    @try {
        PMJankLayerMutationCount += 1;
        NSString *layerClass = PMClassName(layer);
        PMJankLastLayerClass = [layerClass copy] ?: @"";
        PMJankRecordActivity(event ?: @"CALayer.mutation", layerClass, NO);
    } @catch (__unused NSException *e) {}
}

static void PMJankRecordPropertyAnimator(NSString *event) {
#if !PM_ENABLE_DIAGNOSTIC_PROBES
    return;
#endif
    if (!PMIsTargetProcess()) return;
    PMJankPropertyAnimatorCount += 1;
    PMJankRecordActivity(event ?: @"UIViewPropertyAnimator", @"UIViewPropertyAnimator", YES);
}

static void PMJankRecordDisplayLinkTarget(NSString *targetClass) {
#if !PM_ENABLE_DIAGNOSTIC_PROBES
    return;
#endif
    if (!PMIsTargetProcess()) return;
    PMJankDisplayLinkCreateCount += 1;
    PMJankLastDisplayLinkTargetClass = [targetClass copy] ?: @"";
    PMJankRecordActivity(@"CADisplayLink.displayLinkWithTarget", targetClass ?: @"", YES);
}

static NSString *PMFPSProbeLogPath(void) {
    return @"/var/mobile/Library/Preferences/com.promotion120.fpsprobe.plist";
}

static void PMFPSWrite(void) {
#if !PM_ENABLE_DIAGNOSTIC_PROBES
    return;
#endif
    if (PMFPSLastWrite > 0 && (CFAbsoluteTimeGetCurrent() - PMFPSLastWrite) < 0.50) return;
    PMFPSLastWrite = CFAbsoluteTimeGetCurrent();
    PMFPSWriteCount += 1;
    if (PMFPSLastPreferred > 0 && PMFPSLastPreferred < 60) PMFPSLowFPSDropCount += 1;
    @try {
        NSMutableDictionary *root = [NSMutableDictionary dictionaryWithContentsOfFile:PMFPSProbeLogPath()];
        if (!root) root = [NSMutableDictionary dictionary];
        root[@"version"] = PM_SCOPEPROBE_VERSION;
        root[@"bundleID"] = PMBundleID();
        root[@"lastEvent"] = PMFPSLastEvent ?: @"";
        root[@"lastReason"] = PMFPSLastReason ?: @"";
        root[@"lastScene"] = PMFPSLastSceneName ?: @"";
        root[@"lastRangeMin"] = @(PMFPSLastMin);
        root[@"lastRangePreferred"] = @(PMFPSLastPreferred);
        root[@"lastRangeMax"] = @(PMFPSLastMax);
        root[@"lastOrigMin"] = @(PMFPSLastOrigMin);
        root[@"lastOrigPreferred"] = @(PMFPSLastOrigPreferred);
        root[@"lastOrigMax"] = @(PMFPSLastOrigMax);
        root[@"totalOverrides"] = @(PMFPSOverriddenCount);
        root[@"lastOrigFPS"] = @(PMFPSLastOrigFPS);
        root[@"lastAppliedFPS"] = @(PMFPSLastAppliedFPS);
        root[@"lastOrigFrameInterval"] = @(PMFPSLastOrigInterval);
        root[@"lastAppliedFrameInterval"] = @(PMFPSLastAppliedInterval);
        root[@"totalFPSSet"] = @(PMFPSFPSSetCount);
        root[@"totalFrameIntervalSet"] = @(PMFPSFrameIntervalSetCount);
        root[@"actualLastDeltaMs"] = @(PMActualLastDeltaMs);
        root[@"actualMaxDeltaMs"] = @(PMActualMaxDeltaMs);
        root[@"actualLastDurationMs"] = @(PMActualLastDurationMs);
        root[@"actualTickCount"] = @(PMActualTickCount);
        root[@"actualLowTickCount"] = @(PMActualLowTickCount);
        root[@"actualVeryLowTickCount"] = @(PMActualVeryLowTickCount);
        root[@"actualIgnoredLongGapCount"] = @(PMActualIgnoredLongGapCount);
        root[@"actualLastLowDeltaMs"] = @(PMActualLastLowDeltaMs);
        root[@"actualLastLowDurationMs"] = @(PMActualLastLowDurationMs);
        root[@"actualMaxFilteredDeltaMs"] = @(PMActualMaxFilteredDeltaMs);
        root[@"actualLastLowTimestamp"] = @(PMActualLastLowTimestamp);
        root[@"actualLastLowRunLoopMode"] = PMJankLastLowRunLoopMode ?: @"";
        root[@"jankLastRunLoopMode"] = PMJankLastRunLoopMode ?: @"";
        root[@"jankLastActivity"] = PMJankLastActivity ?: @"";
        root[@"jankLastActivityClass"] = PMJankLastActivityClass ?: @"";
        root[@"jankLastActivityAgeMs"] = @(PMJankLastActivityAgeMs());
        root[@"jankLastScrollClass"] = PMJankLastScrollClass ?: @"";
        root[@"jankLastListClass"] = PMJankLastListClass ?: @"";
        root[@"jankLastViewClass"] = PMJankLastViewClass ?: @"";
        root[@"jankLastLayerClass"] = PMJankLastLayerClass ?: @"";
        root[@"jankLastAnimationClass"] = PMJankLastAnimationClass ?: @"";
        root[@"jankLastAnimationKey"] = PMJankLastAnimationKey ?: @"";
        root[@"jankLastDisplayLinkTargetClass"] = PMJankLastDisplayLinkTargetClass ?: @"";
        root[@"jankLastContentOffset"] = PMProbePointDict(PMJankLastContentOffset);
        root[@"jankLastContentSize"] = PMProbeSizeDict(PMJankLastContentSize);
        root[@"jankLastViewFrame"] = PMProbeRectDict(PMJankLastViewFrame);
        root[@"jankLastViewBounds"] = PMProbeRectDict(PMJankLastViewBounds);
        root[@"jankScrollDragging"] = @(PMJankLastScrollDragging);
        root[@"jankScrollTracking"] = @(PMJankLastScrollTracking);
        root[@"jankScrollDecelerating"] = @(PMJankLastScrollDecelerating);
        root[@"jankCounts"] = @{
            @"activity": @(PMJankActivityCount),
            @"scrollOffset": @(PMJankScrollOffsetCount),
            @"listLayout": @(PMJankListLayoutCount),
            @"listReload": @(PMJankListReloadCount),
            @"viewFrame": @(PMJankViewFrameCount),
            @"viewBounds": @(PMJankViewBoundsCount),
            @"layerAnimation": @(PMJankLayerAnimationCount),
            @"layerMutation": @(PMJankLayerMutationCount),
            @"propertyAnimator": @(PMJankPropertyAnimatorCount),
            @"displayLinkCreate": @(PMJankDisplayLinkCreateCount)
        };
        root[@"lastTimestamp"] = [[NSDate date] description];
        root[@"totalWrites"] = @(PMFPSWriteCount);
        root[@"totalLowFPSDrops"] = @(PMFPSLowFPSDropCount);
        root[@"totalRangeSet"] = @(PMFPSRangeSetCount);
        root[@"totalSourceApply"] = @(PMFPSSourceApplyCount);
        root[@"totalGlobalApply"] = @(PMFPSGlobalApplyCount);
        root[@"windowConfirmed"] = @YES;
        root[@"globalEnabled"] = @YES;
        NSMutableArray *events = [root[@"events"] isKindOfClass:[NSMutableArray class]] ? root[@"events"] : [NSMutableArray array];
        [events addObject:@{
            @"event": PMFPSLastEvent ?: @"",
            @"reason": PMFPSLastReason ?: @"",
            @"origMin": @(PMFPSLastOrigMin),
            @"origPref": @(PMFPSLastOrigPreferred),
            @"origMax": @(PMFPSLastOrigMax),
            @"min": @(PMFPSLastMin),
            @"preferred": @(PMFPSLastPreferred),
            @"max": @(PMFPSLastMax),
            @"origFPS": @(PMFPSLastOrigFPS),
            @"appliedFPS": @(PMFPSLastAppliedFPS),
            @"origInterval": @(PMFPSLastOrigInterval),
            @"appliedInterval": @(PMFPSLastAppliedInterval),
            @"actualDeltaMs": @(PMActualLastDeltaMs),
            @"actualDurationMs": @(PMActualLastDurationMs),
            @"actualMaxDeltaMs": @(PMActualMaxDeltaMs),
            @"actualMaxFilteredDeltaMs": @(PMActualMaxFilteredDeltaMs),
            @"actualLastLowDeltaMs": @(PMActualLastLowDeltaMs),
            @"actualLastLowDurationMs": @(PMActualLastLowDurationMs),
            @"actualLowTicks": @(PMActualLowTickCount),
            @"actualVeryLowTicks": @(PMActualVeryLowTickCount),
            @"actualIgnoredLongGaps": @(PMActualIgnoredLongGapCount),
            @"actualLastLowRunLoopMode": PMJankLastLowRunLoopMode ?: @"",
            @"jankRunLoopMode": PMJankLastRunLoopMode ?: @"",
            @"jankLastActivity": PMJankLastActivity ?: @"",
            @"jankLastActivityClass": PMJankLastActivityClass ?: @"",
            @"jankLastActivityAgeMs": @(PMJankLastActivityAgeMs()),
            @"jankLastScrollClass": PMJankLastScrollClass ?: @"",
            @"jankLastListClass": PMJankLastListClass ?: @"",
            @"jankLastLayerClass": PMJankLastLayerClass ?: @"",
            @"jankLastAnimationKey": PMJankLastAnimationKey ?: @"",
            @"jankScrollDragging": @(PMJankLastScrollDragging),
            @"jankScrollTracking": @(PMJankLastScrollTracking),
            @"jankScrollDecelerating": @(PMJankLastScrollDecelerating),
            @"ts": [[NSDate date] description]
        }];
        while (events.count > 20) [events removeObjectAtIndex:0];
        root[@"events"] = events;
        [root writeToFile:PMFPSProbeLogPath() atomically:YES];
    } @catch (NSException *exc) { }
}

static void PMFPSRecordRange(NSString *event, NSString *reason, CAFrameRateRange origRange, CAFrameRateRange appliedRange) {
#if !PM_ENABLE_DIAGNOSTIC_PROBES
    return;
#endif
    PMFPSRangeSetCount += 1;
    PMFPSLastEvent = event;
    PMFPSLastReason = reason;
    PMFPSLastOrigMin = origRange.minimum;
    PMFPSLastOrigPreferred = origRange.preferred;
    PMFPSLastOrigMax = origRange.maximum;
    PMFPSLastMin = appliedRange.minimum;
    PMFPSLastPreferred = appliedRange.preferred;
    PMFPSLastMax = appliedRange.maximum;
    if (origRange.minimum != appliedRange.minimum || origRange.preferred != appliedRange.preferred || origRange.maximum != appliedRange.maximum) {
        PMFPSOverriddenCount += 1;
    }
    PMFPSWrite();
}

static void PMFPSRecordSourceApply(NSString *event, NSString *reason) {
#if !PM_ENABLE_DIAGNOSTIC_PROBES
    return;
#endif
    PMFPSSourceApplyCount += 1;
    PMFPSLastEvent = event;
    PMFPSLastReason = reason;
    PMFPSWrite();
}

static void PMFPSRecordGlobalApply(NSString *event, NSString *reason) {
#if !PM_ENABLE_DIAGNOSTIC_PROBES
    return;
#endif
    PMFPSGlobalApplyCount += 1;
    PMFPSLastEvent = event;
    PMFPSLastReason = reason;
    PMFPSWrite();
}

@interface PMActualProbeTarget : NSObject
@end

@implementation PMActualProbeTarget

- (void)pm_actualProbeTick:(CADisplayLink *)link {
    CFTimeInterval ts = link.timestamp;
    if (PMActualLastTimestamp > 0 && ts > PMActualLastTimestamp) {
        double deltaMs = (ts - PMActualLastTimestamp) * 1000.0;
        // Ignore long gaps from lock/sleep/resume/runloop suspension; they are not visual scroll jank.
        if (deltaMs > 250.0) {
            PMActualIgnoredLongGapCount += 1;
            PMActualLastTimestamp = ts;
            return;
        }
        PMJankLastRunLoopMode = [PMJankCopyMainRunLoopModeName() copy] ?: @"";
        PMActualLastDeltaMs = deltaMs;
        PMActualLastDurationMs = link.duration * 1000.0;
        PMActualTickCount += 1;
        if (deltaMs > PMActualMaxDeltaMs) PMActualMaxDeltaMs = deltaMs;
        if (deltaMs > PMActualMaxFilteredDeltaMs) PMActualMaxFilteredDeltaMs = deltaMs;
        if (deltaMs > 25.0) {
            PMActualLowTickCount += 1;
            PMActualLastLowTimestamp = ts;
            PMActualLastLowDeltaMs = deltaMs;
            PMActualLastLowDurationMs = PMActualLastDurationMs;
            PMJankLastLowRunLoopMode = [PMJankLastRunLoopMode copy] ?: @"";
            if (deltaMs > 30.0) PMActualVeryLowTickCount += 1;
            PMFPSLastEvent = @"ActualDisplayLink.lowTick";
            PMFPSLastReason = PMBannerWindowConfirmed ? @"bannerActive" : @"global";
            PMFPSWrite();
        } else if ((PMActualTickCount % 120) == 0) {
            PMFPSLastEvent = @"ActualDisplayLink.tick";
            PMFPSLastReason = PMBannerWindowConfirmed ? @"bannerActive" : @"global";
            PMFPSWrite();
        }
    }
    PMActualLastTimestamp = ts;
}

@end

__attribute__((unused)) static void PMActualProbeStart(void) {
    if (!PMIsTargetProcess() || PMActualProbeLink) return;
    @try {
        PMActualProbeTargetInstance = [PMActualProbeTarget new];
        PMActualProbeLink = [CADisplayLink displayLinkWithTarget:PMActualProbeTargetInstance selector:@selector(pm_actualProbeTick:)];
        if ([PMActualProbeLink respondsToSelector:@selector(setPreferredFrameRateRange:)]) {
            PMActualProbeLink.preferredFrameRateRange = PMForce120Range();
        } else if ([PMActualProbeLink respondsToSelector:@selector(setPreferredFramesPerSecond:)]) {
            PMActualProbeLink.preferredFramesPerSecond = TARGET_FPS;
        }
        [PMActualProbeLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
        PMFPSLastEvent = @"ActualDisplayLink.start";
        PMFPSLastReason = @"actualProbe";
        PMFPSWrite();
    } @catch (NSException *exc) { }
}

static void PMProbeWriteState(NSString *event, NSString *note, BOOL force) {
    // DISABLED: prevents SIGSEGV from object retention in animation callbacks
    return;
    if (!PMProbeIsWeChat()) return;
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    if (!force && PMProbeLastWriteTime > 0 && (now - PMProbeLastWriteTime) < 0.20) return;
    PMProbeLastWriteTime = now;
    PMProbeLastEvent = [event copy] ?: @"";
    PMProbeLastNote = [note copy] ?: @"";
    @synchronized([NSUserDefaults class]) {
        NSMutableDictionary *root = PMProbeLoadRoot();
        NSDictionary *snapshot = PMProbeEventSnapshot(PMProbeLastEvent, PMProbeLastNote);
        NSMutableArray *events = [NSMutableArray array];
        NSArray *oldEvents = root[@"events"];
        if ([oldEvents isKindOfClass:[NSArray class]]) [events addObjectsFromArray:oldEvents];
        [events addObject:snapshot];
        while (events.count > 80) [events removeObjectAtIndex:0];
        root[@"events"] = events;
        root[@"state"] = @{
            @"event": PMProbeLastEvent ?: @"",
            @"note": PMProbeLastNote ?: @"",
            @"timestamp": [[NSDate date] description],
            @"lastViewControllerClass": PMProbeLastViewControllerClass ?: @"",
            @"lastViewClass": PMProbeLastViewClass ?: @"",
            @"lastPresentedViewControllerClass": PMProbeLastPresentedViewControllerClass ?: @"",
            @"lastNavigationPushedClass": PMProbeLastNavigationPushedClass ?: @"",
            @"lastWindowClass": PMProbeLastWindowClass ?: @"",
            @"lastRootViewControllerClass": PMProbeLastRootViewControllerClass ?: @"",
            @"lastDisplayLinkTargetClass": PMProbeLastDisplayLinkTargetClass ?: @"",
            @"lastLayerClass": PMProbeLastLayerClass ?: @"",
            @"lastAnimationClass": PMProbeLastAnimationClass ?: @"",
            @"lastAnimationKey": PMProbeLastAnimationKey ?: @"",
            @"lastCollectionClass": PMProbeLastCollectionClass ?: @"",
            @"lastTableClass": PMProbeLastTableClass ?: @"",
            @"lastFrame": PMProbeRectDict(PMProbeLastFrame),
            @"lastBounds": PMProbeRectDict(PMProbeLastBounds),
            @"lastPosition": PMProbePointDict(PMProbeLastPosition),
            @"lastContentOffset": PMProbePointDict(PMProbeLastContentOffset),
            @"lastContentSize": PMProbeSizeDict(PMProbeLastContentSize),
            @"lastRange": @{
                @"minimum": @(PMProbeLastRangeMinimum),
                @"preferred": @(PMProbeLastRangePreferred),
                @"maximum": @(PMProbeLastRangeMaximum)
            },
            @"lastPreferredFPS": @(PMProbeLastPreferredFPS),
            @"lastFrameInterval": @(PMProbeLastFrameInterval),
            @"eventCount": @(events.count),
            @"counts": @{
                @"injected": @(PMProbeInjectedCount),
                @"uiScreenMaxQuery": @(PMProbeUIScreenMaxQueryCount),
                @"displayLinkCreate": @(PMProbeDisplayLinkCreateCount),
                @"displayLinkRangeSet": @(PMProbeDisplayLinkRangeSetCount),
                @"displayLinkFPSSet": @(PMProbeDisplayLinkFPSSetCount),
                @"displayLinkFrameIntervalSet": @(PMProbeDisplayLinkFrameIntervalSetCount),
                @"animationRangeSet": @(PMProbeAnimationRangeSetCount),
                @"layerAddAnimation": @(PMProbeLayerAddAnimationCount),
                @"layerSetBounds": @(PMProbeLayerSetBoundsCount),
                @"layerSetPosition": @(PMProbeLayerSetPositionCount),
                @"layerSetTransform": @(PMProbeLayerSetTransformCount),
                @"viewDidAppear": @(PMProbeViewDidAppearCount),
                @"presentViewController": @(PMProbePresentViewControllerCount),
                @"pushViewController": @(PMProbePushViewControllerCount),
                @"windowSetFrame": @(PMProbeWindowSetFrameCount),
                @"windowSetBounds": @(PMProbeWindowSetBoundsCount),
                @"viewSetFrame": @(PMProbeViewSetFrameCount),
                @"viewSetBounds": @(PMProbeViewSetBoundsCount),
                @"scrollSetContentOffset": @(PMProbeScrollSetContentOffsetCount),
                @"propertyAnimatorStart": @(PMProbePropertyAnimatorStartCount),
                @"collectionReload": @(PMProbeCollectionReloadCount),
                @"collectionLayout": @(PMProbeCollectionLayoutCount),
                @"tableReload": @(PMProbeTableReloadCount),
                @"tableLayout": @(PMProbeTableLayoutCount),
                @"metalDrawablePresent": @(PMProbeMetalDrawablePresentCount),
                @"commandBufferPresent": @(PMProbeCommandBufferPresentCount)
            },
            @"windows": PMProbeWindowSummary()
        };
        [root writeToFile:PM_WECHAT_PROBE_LOG_PATH atomically:YES];
    }
}

__attribute__((unused)) static void PMProbeRecordRange(NSString *event, CAFrameRateRange range) {
    if (!PMProbeIsWeChat()) return;
    PMProbeLastRangeMinimum = range.minimum;
    PMProbeLastRangePreferred = range.preferred;
    PMProbeLastRangeMaximum = range.maximum;
    PMProbeWriteState(event, @"range", NO);
}

#define PM_FLOAT_PROBE_TARGET_PACKAGE @"com.be-huge.floating-view"
#define PM_FLOAT_PROBE_SPRINGBOARD_LOG_PATH @"/var/mobile/Library/Preferences/com.promotion120.scopeprobe.springboard.plist"
#define PM_FLOAT_PROBE_PLUGIN_LOG_PATH @"/var/mobile/Library/Preferences/com.promotion120.scopeprobe.com.be-huge.floating-view.plist"
#define PM_FLOAT_PROBE_WECHAT_LOG_PATH @"/var/mobile/Library/Preferences/com.promotion120.scopeprobe.com.tencent.xin.plist"
#define PM_FLOAT_PROBE_FILZA_LOG_PATH @"/var/mobile/Library/Preferences/com.promotion120.scopeprobe.filza.plist"

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
// Create counter retained for probe schema only (Float no longer owns a DynamicSource).
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

// === Global Display Source for SpringBoard (minimal, safe) ===
