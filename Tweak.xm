#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
#import <dispatch/dispatch.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <substrate.h>
#import <rootless.h>
#import <Metal/Metal.h>

#define TWEAK_NAME @"ProMotion120"
#define TARGET_FPS 120

#ifndef __IPHONE_15_0
typedef struct {
    float minimum;
    float preferred;
    float maximum;
} CAFrameRateRange;
#endif

@interface CADisplay : NSObject
+ (CADisplay *)mainDisplay;
@property (nonatomic, readonly) NSArray *availableModes;
@end

@interface CADisplayMode : NSObject
@property (nonatomic, readonly) double refreshRate;
@end

static BOOL PMBannerLifecycleActive = NO;
static BOOL PMBannerWindowConfirmed = NO;
static CFAbsoluteTime PMBannerArmUntil = 0;
static NSUInteger PMBannerSession = 0;
static __weak id PMCurrentBannerPresentable = nil;
static uintptr_t PMCurrentBannerPresentablePtr = 0;
static __weak UIWindow *PMCurrentBannerWindow = nil;
static __weak id PMCurrentBannerScene = nil;
static id PMBannerDynamicFrameRateSource = nil;
static CFAbsoluteTime PMBannerLastSourceApplyAt = 0;

static NSString *PMBundleID(void) {
    static NSString *bundleID = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        bundleID = [[[NSBundle mainBundle] bundleIdentifier] copy] ?: @"";
    });
    return bundleID;
}

static BOOL PMIsTargetProcess(void) {
    static int cached = -1;
    if (cached < 0) cached = [PMBundleID() isEqualToString:@"com.apple.springboard"] ? 1 : 0;
    return cached == 1;
}

static BOOL PMIsArmed(void) {
    return CFAbsoluteTimeGetCurrent() < PMBannerArmUntil;
}

static BOOL PMIsAppProcessEligible(void) {
    // Returns YES for any UIKit app (Filza, WeChat, etc.)
    // This is the primary high-refresh path for app processes.
    // Note: SpringBoard process returns NO here (see PMIsTargetProcess).
    return !PMIsTargetProcess();
}

static BOOL PMIsEligibleNow(void) {
    return PMIsTargetProcess() && PMBannerWindowConfirmed && PMIsArmed();
}

static BOOL PMIsAppEligibleNow(void) {
    return PMIsAppProcessEligible();
}

static NSString *PMClassName(id obj) {
    if (!obj) return @"";
    return NSStringFromClass([obj class]) ?: @"";
}

static BOOL PMDeviceSupports120Hz(void) {
    static BOOL checked = NO;
    static BOOL supported = NO;
    if (!checked) {
        @autoreleasepool {
            Class CADisplayClass = NSClassFromString(@"CADisplay");
            if (CADisplayClass && [CADisplayClass respondsToSelector:@selector(mainDisplay)]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                CADisplay *display = [CADisplayClass performSelector:@selector(mainDisplay)];
#pragma clang diagnostic pop
                NSArray *modes = display ? [display valueForKey:@"availableModes"] : nil;
                for (id mode in modes) {
                    double rate = [[mode valueForKey:@"refreshRate"] doubleValue];
                    if (rate >= 119.0) {
                        supported = YES;
                        break;
                    }
                }
            }
        }
        checked = YES;
    }
    return supported;
}

static CAFrameRateRange PMForce120Range(void) {
    CAFrameRateRange range;
    // Strict lock: do not leave 80Hz as a legal lower bound.
    range.minimum = TARGET_FPS;
    range.preferred = TARGET_FPS;
    range.maximum = TARGET_FPS;
    return range;
}

// PMGlobal120RangeFromRange removed: identical to PMForce120Range(),
// ignored its input parameter.

typedef void (*PMRangeSetterDyn)(id, SEL, CAFrameRateRange);
typedef void (*PMUIntSetterDyn)(id, SEL, unsigned int);
typedef void (*PMReasonsSetterDyn)(id, SEL, const unsigned int *, NSUInteger);

static void PMSetHighFrameRateReasonIfPossible(id obj, BOOL isDisplayLink, BOOL isDynamicSource) {
    if (!obj || !PMIsEligibleNow()) return;
    @try {
        static SEL singleSel = nil;
        static SEL multiSel = nil;
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            singleSel = NSSelectorFromString(@"setHighFrameRateReason:");
            multiSel = NSSelectorFromString(@"setHighFrameRateReasons:count:");
        });
        if ([obj respondsToSelector:singleSel]) {
            PMUIntSetterDyn fn = (PMUIntSetterDyn)objc_msgSend;
            fn(obj, singleSel, 1U);
        }
        if ([obj respondsToSelector:multiSel]) {
            unsigned int reasons[1] = { 1U };
            PMReasonsSetterDyn fn = (PMReasonsSetterDyn)objc_msgSend;
            fn(obj, multiSel, reasons, (NSUInteger)1);
        }
    } @catch (__unused NSException *e) {
    }
}

static void PMSetFrameRateRangeIfPossible(id obj, BOOL isDisplayLink, BOOL isDynamicSource) {
    if (!obj || !PMIsEligibleNow()) return;
    @try {
        static SEL sel = nil;
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            sel = NSSelectorFromString(@"setPreferredFrameRateRange:");
        });
        if ([obj respondsToSelector:sel]) {
            PMRangeSetterDyn fn = (PMRangeSetterDyn)objc_msgSend;
            fn(obj, sel, PMForce120Range());
        }
    } @catch (__unused NSException *e) {
    }
}

static void PMApplyToCAObject(id obj, BOOL isDisplayLink, BOOL isDynamicSource) {
    PMSetHighFrameRateReasonIfPossible(obj, isDisplayLink, isDynamicSource);
    PMSetFrameRateRangeIfPossible(obj, isDisplayLink, isDynamicSource);
}

static void PMSetHighFrameRateReasonDirect(id obj) {
    if (!obj) return;
    @try {
        static SEL singleSel = nil;
        static SEL multiSel = nil;
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            singleSel = NSSelectorFromString(@"setHighFrameRateReason:");
            multiSel = NSSelectorFromString(@"setHighFrameRateReasons:count:");
        });
        if ([obj respondsToSelector:singleSel]) {
            PMUIntSetterDyn fn = (PMUIntSetterDyn)objc_msgSend;
            fn(obj, singleSel, 1U);
        }
        if ([obj respondsToSelector:multiSel]) {
            unsigned int reasons[1] = { 1U };
            PMReasonsSetterDyn fn = (PMReasonsSetterDyn)objc_msgSend;
            fn(obj, multiSel, reasons, (NSUInteger)1);
        }
    } @catch (__unused NSException *e) {
    }
}

static void PMSetFrameRateRangeDirect(id obj) {
    if (!obj) return;
    @try {
        static SEL sel = nil;
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            sel = NSSelectorFromString(@"setPreferredFrameRateRange:");
        });
        if ([obj respondsToSelector:sel]) {
            PMRangeSetterDyn fn = (PMRangeSetterDyn)objc_msgSend;
            fn(obj, sel, PMForce120Range());
        }
    } @catch (__unused NSException *e) {
    }
}

static void PMApplyToCAObjectDirect(id obj) {
    PMSetHighFrameRateReasonDirect(obj);
    PMSetFrameRateRangeDirect(obj);
}

static id PMMainCADisplay(void) {
    Class CADisplayClass = NSClassFromString(@"CADisplay");
    if (!CADisplayClass || ![CADisplayClass respondsToSelector:@selector(mainDisplay)]) return nil;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    id display = [CADisplayClass performSelector:@selector(mainDisplay)];
#pragma clang diagnostic pop
    return display;
}

// Forward declarations for FPS probe (defined later)
static void PMFPSRecordRange(NSString *event, NSString *reason, CAFrameRateRange origRange, CAFrameRateRange appliedRange);
static void PMFPSRecordSourceApply(NSString *event, NSString *reason);
static void PMFPSRecordGlobalApply(NSString *event, NSString *reason);

static void PMApplyDisplayFrameRateSource(NSString *source) {
    if (!PMIsEligibleNow()) return;
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    if (PMBannerLastSourceApplyAt > 0 && (now - PMBannerLastSourceApplyAt) < 0.10) return;
    @try {
        if (!PMBannerDynamicFrameRateSource) {
            Class SourceClass = NSClassFromString(@"CADynamicFrameRateSource");
            id display = PMMainCADisplay();
            if (SourceClass && display) {
                id allocated = [SourceClass alloc];
                SEL initSel = NSSelectorFromString(@"initWithDisplay:");
                if ([allocated respondsToSelector:initSel]) {
                    typedef id (*PMInitWithDisplayFn)(id, SEL, id);
                    PMInitWithDisplayFn fn = (PMInitWithDisplayFn)objc_msgSend;
                    PMBannerDynamicFrameRateSource = fn(allocated, initSel, display);
                }
            }
        }
        if (PMBannerDynamicFrameRateSource) {
            PMSetHighFrameRateReasonIfPossible(PMBannerDynamicFrameRateSource, NO, YES);
            PMSetFrameRateRangeIfPossible(PMBannerDynamicFrameRateSource, NO, YES);
            PMBannerLastSourceApplyAt = now;
            PMFPSRecordSourceApply(@"bannerDisplaySource", source ?: @"unknown");
        }
    } @catch (__unused NSException *e) {
    }
}

static void PMReleaseDisplayFrameRateSource(NSString *source) {
    if (!PMBannerDynamicFrameRateSource) return;
    id sourceObject = PMBannerDynamicFrameRateSource;
    PMBannerDynamicFrameRateSource = nil;
    @try {
        SEL multiSel = NSSelectorFromString(@"setHighFrameRateReasons:count:");
        if ([sourceObject respondsToSelector:multiSel]) {
            PMReasonsSetterDyn fn = (PMReasonsSetterDyn)objc_msgSend;
            fn(sourceObject, multiSel, NULL, (NSUInteger)0);
        }
    } @catch (__unused NSException *e) {
    }
}

static BOOL PMLayerBelongsToBannerWindow(CALayer *layer) {
    if (!layer || !PMCurrentBannerWindow) return NO;
    CALayer *root = PMCurrentBannerWindow.layer;
    for (CALayer *cursor = layer; cursor; cursor = cursor.superlayer) {
        if (cursor == root) return YES;
    }
    return NO;
}

static BOOL PMConfirmWindowIfBanner(UIWindow *window, NSString *source) {
    NSString *cls = PMClassName(window);
    if (!window) return NO;
    if ([cls isEqualToString:@"SBBannerWindow"]) {
        PMCurrentBannerWindow = window;
        PMBannerWindowConfirmed = YES;
        PMBannerArmUntil = CFAbsoluteTimeGetCurrent() + 3.0;
        if ([window respondsToSelector:@selector(windowScene)]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            PMCurrentBannerScene = [window performSelector:@selector(windowScene)];
#pragma clang diagnostic pop
        }
        PMApplyDisplayFrameRateSource(source ?: @"confirmWindow.displaySource");
        return YES;
    }
    return NO;
}

static BOOL PMCaptureWindowFromView(id view, NSString *source) {
    if (!PMIsTargetProcess() || !view || ![view respondsToSelector:@selector(window)]) return NO;
    @try {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        UIWindow *window = [view performSelector:@selector(window)];
#pragma clang diagnostic pop
        return PMConfirmWindowIfBanner(window, source);
    } @catch (__unused NSException *e) {
        return NO;
    }
}

static BOOL PMCaptureFromPresentable(id presentable, NSString *source) {
    if (!PMIsTargetProcess() || !presentable || ![presentable respondsToSelector:@selector(view)]) return NO;
    @try {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        id view = [presentable performSelector:@selector(view)];
#pragma clang diagnostic pop
        return PMCaptureWindowFromView(view, source);
    } @catch (__unused NSException *e) {
        return NO;
    }
}

static BOOL PMScanApplicationWindows(NSString *source) {
    if (!PMIsTargetProcess()) return NO;
    @try {
        Class UIApplicationClass = NSClassFromString(@"UIApplication");
        if (!UIApplicationClass || ![UIApplicationClass respondsToSelector:@selector(sharedApplication)]) return NO;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        UIApplication *app = [UIApplicationClass performSelector:@selector(sharedApplication)];
#pragma clang diagnostic pop
        if (!app || ![app respondsToSelector:@selector(windows)]) return NO;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        NSArray *windows = [app performSelector:@selector(windows)];
#pragma clang diagnostic pop
        for (UIWindow *window in windows) {
            if ([PMClassName(window) isEqualToString:@"SBBannerWindow"]) {
                return PMConfirmWindowIfBanner(window, source ?: @"scanApplicationWindows");
            }
        }
    } @catch (__unused NSException *e) {
    }
    return NO;
}

static void PMScheduleCapture(id presentable, NSString *source) {
    if (!PMIsTargetProcess()) return;
    id capturedPresentable = presentable;
    NSString *capturedSource = [source copy] ?: @"capture";
    if (!PMCaptureFromPresentable(capturedPresentable, [capturedSource stringByAppendingString:@".presentable"])) {
        PMScanApplicationWindows([capturedSource stringByAppendingString:@".windows"]);
    }
    NSArray *delays = @[@0.03, @0.08, @0.16];
    for (NSNumber *delayNumber in delays) {
        double delay = delayNumber.doubleValue;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (!PMBannerLifecycleActive && !PMIsArmed()) return;
            NSString *suffix = [NSString stringWithFormat:@".delayed%.2f", delay];
            if (!PMCaptureFromPresentable(capturedPresentable, [capturedSource stringByAppendingString:[suffix stringByAppendingString:@".presentable"]])) {
                PMScanApplicationWindows([capturedSource stringByAppendingString:[suffix stringByAppendingString:@".windows"]]);
            }
        });
    }
}

static void PMScheduleDisplaySourceReapply(NSString *source, NSArray<NSNumber *> *delays) {
    NSUInteger scheduledSession = PMBannerSession;
    for (NSNumber *delayNumber in delays) {
        double delay = delayNumber.doubleValue;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (scheduledSession != PMBannerSession) return;
            if (!PMIsArmed() || !PMBannerWindowConfirmed) return;
            PMApplyDisplayFrameRateSource(source ?: @"displaySource.reapply");
        });
    }
}

static void PMExtendExitTailAndApply(NSString *source) {
    if (!PMBannerWindowConfirmed) return;
    PMBannerArmUntil = MAX(PMBannerArmUntil, CFAbsoluteTimeGetCurrent() + 1.65);
    PMApplyDisplayFrameRateSource(source ?: @"exitTail.apply");
    PMScheduleDisplaySourceReapply(source ?: @"exitTail.reapply", @[@0.05, @0.18, @0.36, @0.72, @1.10]);
}

static uintptr_t PMPresentablePointer(id presentable) {
    return (uintptr_t)(__bridge void *)presentable;
}

static BOOL PMFindBannerWindowForExitPoll(NSString *source) {
    if (!PMIsTargetProcess()) return NO;
    @try {
        Class UIApplicationClass = NSClassFromString(@"UIApplication");
        if (!UIApplicationClass || ![UIApplicationClass respondsToSelector:@selector(sharedApplication)]) return NO;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        UIApplication *app = [UIApplicationClass performSelector:@selector(sharedApplication)];
#pragma clang diagnostic pop
        if (!app || ![app respondsToSelector:@selector(windows)]) return NO;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        NSArray *windows = [app performSelector:@selector(windows)];
#pragma clang diagnostic pop
        for (UIWindow *window in windows) {
            if ([PMClassName(window) isEqualToString:@"SBBannerWindow"]) {
                PMCurrentBannerWindow = window;
                PMBannerWindowConfirmed = YES;
                if ([window respondsToSelector:@selector(windowScene)]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                    PMCurrentBannerScene = [window performSelector:@selector(windowScene)];
#pragma clang diagnostic pop
                }
                return YES;
            }
        }
    } @catch (__unused NSException *e) {
    }
    return NO;
}

static void PMFinishExitPollRelease(NSString *source, BOOL timeout) {
    PMBannerWindowConfirmed = NO;
    PMBannerArmUntil = 0;
    PMCurrentBannerPresentablePtr = 0;
    PMCurrentBannerPresentable = nil;
    PMReleaseDisplayFrameRateSource(source ?: @"exitPoll.release");
}

static void PMScheduleExitPollRelease(NSUInteger endingSession, CFAbsoluteTime startedAt, NSUInteger missingCount) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.12 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (endingSession != PMBannerSession || PMBannerLifecycleActive) return;

        CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
        BOOL timedOut = (now - startedAt) >= 4.0;
        BOOL found = PMFindBannerWindowForExitPoll(@"exitPoll.scan");

        PMBannerArmUntil = MAX(PMBannerArmUntil, now + 0.35);
        PMBannerWindowConfirmed = YES;
        PMApplyDisplayFrameRateSource(@"exitPoll.reapplyDisplaySource");

        if (timedOut) {
            PMFinishExitPollRelease(@"exitPoll.timeoutReleaseDisplaySource", YES);
            return;
        }

        NSUInteger nextMissingCount = found ? 0 : (missingCount + 1);
        if ((now - startedAt) >= 0.70 && nextMissingCount >= 2) {
            PMFinishExitPollRelease(@"exitPoll.windowGoneReleaseDisplaySource", NO);
            return;
        }

        PMScheduleExitPollRelease(endingSession, startedAt, nextMissingCount);
    });
}

static BOOL PMPresentableMatchesCurrent(id presentable) {
    uintptr_t endingPtr = PMPresentablePointer(presentable);
    uintptr_t currentPtr = PMCurrentBannerPresentablePtr;
    if (!endingPtr || !currentPtr) return YES;
    return endingPtr == currentPtr;
}

static void PMBeginBannerSession(NSString *event, id presentable) {
    PMBannerLifecycleActive = YES;
    PMBannerSession += 1;
    PMCurrentBannerPresentable = presentable;
    PMCurrentBannerPresentablePtr = PMPresentablePointer(presentable);
    PMBannerArmUntil = CFAbsoluteTimeGetCurrent() + 1.2;
    PMScheduleCapture(presentable, event);
}

static void PMEndBannerSession(NSString *event, NSString *note, id presentable) {
    if (!PMPresentableMatchesCurrent(presentable)) {
        PMExtendExitTailAndApply(@"endBanner.staleEndKeepCurrentAlive");
        return;
    }

    PMBannerLifecycleActive = NO;
    if (PMBannerWindowConfirmed) {
        NSUInteger endingSession = PMBannerSession;
        CFAbsoluteTime startedAt = CFAbsoluteTimeGetCurrent();
        PMExtendExitTailAndApply(@"endBanner.exitTailApply");
        PMScheduleExitPollRelease(endingSession, startedAt, 0);
    }
}



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
static NSUInteger PMFloatSourceCreateCount = 0;
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
static BOOL PMFloatWindowConfirmed = NO;
static id PMGlobalSBDisplaySource = nil;
static NSUInteger PMGlobalSBCreateCount = 0;
static NSUInteger PMGlobalSBApplyCount = 0;
static BOOL PMGlobalSBEnabled = NO;
static CFAbsoluteTime PMGlobalLastApply = 0;

// === Persistent SpringBoard DisplayLink: keeps DPPMS from downclocking ===
// A running CADisplayLink in SpringBoard acts as a live 120Hz consumer.
// DPPMS treats active display links as proof of demand; a mere
// CADynamicFrameRateSource vote can be overridden when the foreground
// app (injection-blocked) only produces 60fps content.
// === Smart keepalive: only burn render-dirty when an app is in foreground ===
// On the home screen, SpringBoard's own hooks handle 120Hz directly.
// The keepalive is only needed when a (potentially injection-blocked) app is frontmost.
static BOOL PMSBIsAppInForeground(void) {
    @try {
        Class cls = NSClassFromString(@"SBApplicationController");
        if (!cls) return YES;
        SEL sharedSel = NSSelectorFromString(@"sharedInstance");
        if (![cls respondsToSelector:sharedSel]) return YES;
        typedef id (*PMIdGetter)(id, SEL);
        PMIdGetter getter = (PMIdGetter)objc_msgSend;
        id controller = getter((id)cls, sharedSel);
        if (!controller) return YES;
        SEL frontSel = NSSelectorFromString(@"frontmostApplication");
        if (![controller respondsToSelector:frontSel]) {
            frontSel = NSSelectorFromString(@"frontApp");
            if (![controller respondsToSelector:frontSel]) return YES;
        }
        return getter(controller, frontSel) != nil;
    } @catch (__unused NSException *e) {}
    return YES;
}

@interface PMSBKeepAliveTarget : NSObject
@end
@implementation PMSBKeepAliveTarget
- (void)pm_sbTick:(__unused CADisplayLink *)link {
    // Toggle a sub-pixel property on a tiny offscreen layer to create
    // a real render-dirty commit each frame.  DPPMS checks actual
    // content production, not just DisplayLink existence.
    static CALayer *dirtyLayer = nil;
    static UIWindow *keepAliveWindow = nil;
    static BOOL toggle = NO;
    static NSUInteger frameCount = 0;
    static BOOL needsKeepAlive = YES;

    frameCount++;
    // Re-evaluate once per second (~120 frames at 120Hz)
    if (frameCount % 120 == 0) {
        needsKeepAlive = PMSBIsAppInForeground();
    }
    if (!needsKeepAlive) return;

    if (!keepAliveWindow) {
        @try {
            keepAliveWindow = [[UIWindow alloc] initWithFrame:CGRectMake(-10, -10, 1, 1)];
            keepAliveWindow.windowLevel = -9999;
            keepAliveWindow.hidden = NO;
            keepAliveWindow.userInteractionEnabled = NO;
            keepAliveWindow.backgroundColor = [UIColor clearColor];
            dirtyLayer = [CALayer layer];
            dirtyLayer.frame = CGRectMake(0, 0, 1, 1);
            dirtyLayer.opacity = 0.01f;
            [keepAliveWindow.layer addSublayer:dirtyLayer];
        } @catch (__unused NSException *e) {}
    }
    if (dirtyLayer.superlayer) {
        toggle = !toggle;
        dirtyLayer.position = CGPointMake(toggle ? 0.0f : 0.5f, 0.0f);
    }
}
@end

static CADisplayLink *PMSBKeepAliveLink = nil;
static PMSBKeepAliveTarget *PMSBKeepAliveTargetInstance = nil;

static void PMSBInstallKeepAliveLink(void) {
    if (PMSBKeepAliveLink || !PMDeviceSupports120Hz()) return;
    @try {
        PMSBKeepAliveTargetInstance = [[PMSBKeepAliveTarget alloc] init];
        PMSBKeepAliveLink = [CADisplayLink displayLinkWithTarget:PMSBKeepAliveTargetInstance selector:@selector(pm_sbTick:)];
        if ([PMSBKeepAliveLink respondsToSelector:@selector(setPreferredFrameRateRange:)]) {
            CAFrameRateRange range;
            range.minimum = 80;
            range.preferred = TARGET_FPS;
            range.maximum = TARGET_FPS;
            [PMSBKeepAliveLink setPreferredFrameRateRange:range];
        } else if ([PMSBKeepAliveLink respondsToSelector:@selector(setPreferredFramesPerSecond:)]) {
            [PMSBKeepAliveLink setPreferredFramesPerSecond:TARGET_FPS];
        }
        [PMSBKeepAliveLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    } @catch (__unused NSException *e) {}
}


static void PMGlobalSBApply(NSString *reason) {
    if (!PMGlobalSBEnabled || !PMDeviceSupports120Hz()) return;
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    if (PMGlobalLastApply > 0 && (now - PMGlobalLastApply) < 0.20) return;
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

static void PMGlobalSBSetup(void) {
    if (PMGlobalSBEnabled) return;
    PMGlobalSBEnabled = YES;
    PMGlobalSBApply(@"setup");
    PMSBInstallKeepAliveLink();
}

static CFAbsoluteTime PMFloatArmUntil = 0;
static NSUInteger PMFloatSession = 0;
static id PMFloatDynamicFrameRateSource = nil;
static BOOL PMFloatVisibleCache = NO;
static CFAbsoluteTime PMFloatVisibleCacheAt = 0;
static CFAbsoluteTime PMFloatLastSourceApplyAt = 0;
static const void *PMFloatDisplayLinkTargetClassKey = &PMFloatDisplayLinkTargetClassKey;

static BOOL PMFloatProbeShouldRecord(void) {
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
    if (!PMFloatProbeShouldRecord()) return @[];
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
    if (!PMFloatProbeShouldRecord()) return;
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
            @"sourceActive": @(PMFloatDynamicFrameRateSource != nil),
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
                @"sourceCreate": @(PMFloatSourceCreateCount),
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
    if (!PMFloatProbeShouldRecord() || !view) return;
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
    if (!PMFloatProbeShouldRecord()) return;
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

static BOOL PMFloatAnyFloatingWindowVisible(void) {
    if (!PMFloatProbeShouldRecord()) return NO;
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
    if (!PMFloatProbeShouldRecord()) return NO;
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
    @try {
        if (!PMFloatDynamicFrameRateSource) {
            Class SourceClass = NSClassFromString(@"CADynamicFrameRateSource");
            id display = PMMainCADisplay();
            if (SourceClass && display) {
                id allocated = [SourceClass alloc];
                SEL initSel = NSSelectorFromString(@"initWithDisplay:");
                if ([allocated respondsToSelector:initSel]) {
                    typedef id (*PMInitWithDisplayFn)(id, SEL, id);
                    PMInitWithDisplayFn fn = (PMInitWithDisplayFn)objc_msgSend;
                    PMFloatDynamicFrameRateSource = fn(allocated, initSel, display);
                    PMFloatSourceCreateCount += 1;
                }
            }
        }
        if (PMFloatDynamicFrameRateSource) {
            CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
            if (PMFloatLastSourceApplyAt <= 0 || (now - PMFloatLastSourceApplyAt) >= 0.10) {
                PMApplyToCAObjectDirect(PMFloatDynamicFrameRateSource);
                PMFloatSourceApplyCount += 1;
                PMFloatLastSourceApplyAt = now;
                PMFloatWriteState(@"floatSource.apply", event ?: @"", NO);
            }
        }
    } @catch (__unused NSException *e) {
    }
}

static void PMFloatArm(NSString *event) {
    PMFloatWindowConfirmed = YES;
    PMFloatSession += 1;
    NSUInteger session = PMFloatSession;
    PMFloatArmUntil = CFAbsoluteTimeGetCurrent() + 1.60;
    PMFloatApplyDisplayFrameRateSource(event);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.75 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        PMFloatReleaseIfExpired(session);
    });
}

static void PMFloatArmForWindow(UIWindow *window, NSString *event) {
    if (!PMFloatShouldArmForWindow(window)) return;
    if (window) {
        PMFloatLastWindowClass = [PMClassName(window) copy];
        PMFloatLastRootViewControllerClass = [PMClassName(window.rootViewController) copy];
    }
    PMFloatArm(event);
}

static void PMFloatArmForView(UIView *view, NSString *event) {
    if (!view || !PMFloatProbeShouldRecord()) return;
    UIWindow *window = nil;
    @try { window = view.window; } @catch (__unused NSException *e) {}
    PMFloatArmForWindow(window, event);
}

static void PMFloatArmForLayer(CALayer *layer, NSString *event) {
    if (!layer || !PMFloatProbeShouldRecord()) return;
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
    if (!PMFloatProbeShouldRecord() || !PMFloatAnyFloatingWindowVisible()) return;
    PMFloatLastPreArmReason = [reason copy] ?: @"";
    PMFloatWindowConfirmed = YES;
    PMFloatSession += 1;
    NSUInteger session = PMFloatSession;
    PMFloatArmUntil = CFAbsoluteTimeGetCurrent() + 2.00;
    PMFloatApplyDisplayFrameRateSource(reason ?: @"prearm");
    PMFloatWriteState(@"floatPreArm", reason ?: @"", YES);
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
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.50 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            PMFloatReleaseIfExpired(session);
        });
        return;
    }
    if (PMFloatDynamicFrameRateSource) {
        // Formally clear the source's reason before releasing, so the system
        // knows this source no longer requests 120Hz.  Call the original IMP
        // directly (bypassing our PMIsManagedSource guard) so the clear
        // actually reaches CoreAnimation.
        @try {
            if (orig_CADynamicFrameRateSource_setHighFrameRateReasons_count) {
                orig_CADynamicFrameRateSource_setHighFrameRateReasons_count(
                    PMFloatDynamicFrameRateSource,
                    NSSelectorFromString(@"setHighFrameRateReasons:count:"),
                    NULL, (NSUInteger)0);
            }
        } @catch (__unused NSException *e) {}
        PMFloatDynamicFrameRateSource = nil;
        PMFloatSourceReleaseCount += 1;
    }
    PMFloatWindowConfirmed = NO;
    PMFloatWriteState(@"floatSource.release", @"expired", YES);
}

// App-process persistent 120Hz source: created once per app launch.
// Unlike the old scroll-only source that was created/destroyed on each scroll,
// this keeps a persistent CADynamicFrameRateSource alive for the entire process
// lifetime. This prevents 120Hz drops during VC transitions, tab switches,
// animations, and other non-scroll scenarios.
static id PMAppPersistentFrameRateSource = nil;
static BOOL PMAppPersistentSourceApplied = NO;

// Helper: is this one of our managed sources that should never be cleared by system?
static inline BOOL PMIsManagedSource(id source) {
    return source == PMGlobalSBDisplaySource
        || source == PMAppPersistentFrameRateSource
        || source == PMFloatDynamicFrameRateSource
        || source == PMBannerDynamicFrameRateSource;
}

static void PMAppEnsurePersistentSource(void) {
    if (PMIsTargetProcess() || PMAppPersistentSourceApplied) return;
    @try {
        Class SourceClass = NSClassFromString(@"CADynamicFrameRateSource");
        id display = PMMainCADisplay();
        if (SourceClass && display) {
            id allocated = [SourceClass alloc];
            SEL initSel = NSSelectorFromString(@"initWithDisplay:");
            if ([allocated respondsToSelector:initSel]) {
                typedef id (*PMInitWithDisplayFn)(id, SEL, id);
                PMInitWithDisplayFn fn = (PMInitWithDisplayFn)objc_msgSend;
                PMAppPersistentFrameRateSource = fn(allocated, initSel, display);
                if (PMAppPersistentFrameRateSource) {
                    PMSetHighFrameRateReasonDirect(PMAppPersistentFrameRateSource);
                    PMSetFrameRateRangeDirect(PMAppPersistentFrameRateSource);
                    PMAppPersistentSourceApplied = YES;
                }
            }
        }
    } @catch (__unused NSException *e) {
    }
}

// Re-apply 120Hz to the persistent source (e.g. after system may have reset it)
// Throttled to avoid per-frame overhead during scrolling.
static CFAbsoluteTime PMAppLastRefreshAt = 0;
static const CFTimeInterval PMAppRefreshMinInterval = 0.20;

static void PMAppRefreshPersistentSource(void) {
    if (PMIsTargetProcess() || !PMAppPersistentFrameRateSource) return;
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    if (PMAppLastRefreshAt > 0 && (now - PMAppLastRefreshAt) < PMAppRefreshMinInterval) return;
    PMAppLastRefreshAt = now;
    @try {
        PMSetHighFrameRateReasonDirect(PMAppPersistentFrameRateSource);
        PMSetFrameRateRangeDirect(PMAppPersistentFrameRateSource);
    } @catch (__unused NSException *e) {
    }
}

// Scroll arm: still used to re-affirm 120Hz during active scrolling,
// but no longer creates/destroys its own source.
static BOOL PMAppScrollViewIsMoving(UIScrollView *scrollView) {
    if (!scrollView) return NO;
    @try {
        return scrollView.dragging || scrollView.tracking || scrollView.decelerating;
    } @catch (__unused NSException *e) {
        return NO;
    }
}

static void PMAppScrollArm(__unused NSString *event) {
    if (PMIsTargetProcess()) return;
    PMAppRefreshPersistentSource();
}

// ============================================================
// Full ProMotion path: global/system 120Hz hooks
// ============================================================
%hook SBProMotionPolicy

- (long long)maximumSupportedRefreshRate {
    return TARGET_FPS;
}

- (long long)effectiveMaxRefreshRate {
    return TARGET_FPS;
}

- (long long)policyRefreshRate {
    return TARGET_FPS;
}

- (BOOL)isLimitFrameRateEnabled {
    return NO;
}

- (BOOL)shouldLimitFrameRate {
    return NO;
}

%end

// Low power mode hooks removed: they globally disable iOS power saving
// across all processes, which is undesirable. SBProMotionPolicy hooks
// are sufficient to unlock 120Hz without breaking battery management.

%hook SBDisplayRefreshRateController

- (long long)maximumRefreshRate {
    return TARGET_FPS;
}

%end

%hook UIScreen

- (NSInteger)maximumFramesPerSecond {
    if (PMDeviceSupports120Hz()) return TARGET_FPS;
    return %orig;
}

%end

%hook CADisplayLink

+ (CADisplayLink *)displayLinkWithTarget:(id)target selector:(SEL)sel {
    CADisplayLink *link = %orig;
    if (PMIsTargetProcess()) {
        PMJankRecordDisplayLinkTarget(PMClassName(target));
    }
    if (!PMIsTargetProcess()) {
        PMFloatDisplayLinkCreateCount += 1;
        PMFloatLastDisplayLinkTargetClass = [PMClassName(target) copy];
        if (link && PMFloatLastDisplayLinkTargetClass) {
            @try { objc_setAssociatedObject(link, PMFloatDisplayLinkTargetClassKey, PMFloatLastDisplayLinkTargetClass, OBJC_ASSOCIATION_COPY_NONATOMIC); } @catch (__unused NSException *e) {}
        }
        if (PMFloatTargetIsInProcessAnimationManager(PMFloatLastDisplayLinkTargetClass) && PMFloatAnyFloatingWindowVisible()) {
            PMFloatPreArmInProcessManagerCount += 1;
            PMFloatPreArm(@"CADisplayLink.UIViewInProcessAnimationManager");
        }
        PMFloatWriteState(@"CADisplayLink.displayLinkWithTarget", PMFloatLastDisplayLinkTargetClass ?: @"", YES);
    }
    if (PMDeviceSupports120Hz() && link) {
        if (PMIsTargetProcess()) {
            // SpringBoard: always apply 120Hz
            // Use banner lifecycle management when banner is active, otherwise direct apply
            if (PMIsEligibleNow()) {
                PMApplyToCAObject(link, YES, NO);
            } else {
                PMApplyToCAObjectDirect(link);
            }
        } else if (PMFloatIsEligibleNow() || PMIsAppEligibleNow()) {
            // Float window or App process: apply 120Hz
            PMApplyToCAObjectDirect(link);
        } else {
            // Fallback: should rarely reach here
            if ([link respondsToSelector:@selector(setPreferredFrameRateRange:)]) {
                CAFrameRateRange range = PMForce120Range();
                [link setPreferredFrameRateRange:range];
            } else if ([link respondsToSelector:@selector(setPreferredFramesPerSecond:)]) {
                [link setPreferredFramesPerSecond:TARGET_FPS];
            }
        }
    }
    return link;
}

- (void)setPreferredFrameRateRange:(CAFrameRateRange)range {
    if (!PMIsTargetProcess()) {
        PMFloatDisplayLinkRangeSetCount += 1;
        PMFloatRecordRange(@"CADisplayLink.setPreferredFrameRateRange", range);
        if (PMFloatAnyFloatingWindowVisible() && ((range.preferred > 0 && range.preferred < TARGET_FPS) || (range.maximum > 0 && range.maximum < TARGET_FPS))) {
            PMFloatPreArmLowFPSCount += 1;
            PMFloatPreArm(@"CADisplayLink.lowRange");
        }
    }
    if (PMDeviceSupports120Hz()) {
        CAFrameRateRange appliedRange;
        if (PMIsTargetProcess()) {
            // SpringBoard: always apply 120Hz
            if (PMIsEligibleNow()) {
                PMSetHighFrameRateReasonIfPossible(self, YES, NO);
            } else {
                PMSetHighFrameRateReasonDirect(self);
            }
            appliedRange = PMForce120Range();
        } else if (PMFloatIsEligibleNow() || PMIsAppEligibleNow()) {
            // Float window or App process: apply 120Hz
            PMSetHighFrameRateReasonDirect(self);
            appliedRange = PMForce120Range();
        } else {
            // Fallback
            appliedRange = PMForce120Range();
        }
        %orig(appliedRange);
    } else {
        %orig;
    }
}

- (void)setPreferredFramesPerSecond:(NSInteger)fps {
    if (!PMIsTargetProcess()) {
        PMFloatDisplayLinkFPSSetCount += 1;
        PMFloatLastPreferredFPS = fps;
        NSString *targetClass = PMFloatDisplayLinkTargetClass(self);
        if (targetClass.length > 0) PMFloatLastDisplayLinkTargetClass = [targetClass copy];
        if (PMFloatAnyFloatingWindowVisible() && fps > 0 && fps < TARGET_FPS) {
            PMFloatPreArmLowFPSCount += 1;
            NSString *reason = PMFloatTargetIsInProcessAnimationManager(targetClass) ? @"CADisplayLink.lowFPS.UIViewInProcessAnimationManager" : @"CADisplayLink.lowFPS";
            PMFloatPreArm(reason);
        }
        PMFloatWriteState(@"CADisplayLink.setPreferredFramesPerSecond", [NSString stringWithFormat:@"fps=%ld target=%@", (long)fps, targetClass ?: @""], NO);
    }
    if (PMDeviceSupports120Hz()) {
#if PM_ENABLE_DIAGNOSTIC_PROBES
        PMFPSFPSSetCount += 1;
        PMFPSLastEvent = @"CADisplayLink.setPreferredFramesPerSecond";
        PMFPSLastReason = PMFloatWindowConfirmed ? @"bannerActive" : @"global";
        PMFPSLastOrigFPS = fps;
        PMFPSLastAppliedFPS = TARGET_FPS;
        if (fps != TARGET_FPS) PMFPSOverriddenCount += 1;
#endif
        // Always apply 120Hz with highFrameRateReason
        if (PMIsTargetProcess()) {
            // SpringBoard
            if (PMIsEligibleNow()) {
                PMSetHighFrameRateReasonIfPossible(self, YES, NO);
            } else {
                PMSetHighFrameRateReasonDirect(self);
            }
        } else if (PMFloatIsEligibleNow() || PMIsAppEligibleNow()) {
            // Float or App (Float has higher priority in check order)
            PMSetHighFrameRateReasonDirect(self);
        }
        %orig(TARGET_FPS);
    } else {
        %orig;
    }
}

- (void)setFrameInterval:(NSInteger)interval {
    if (!PMIsTargetProcess()) {
        PMFloatDisplayLinkFrameIntervalSetCount += 1;
        PMFloatLastFrameInterval = interval;
        PMFloatWriteState(@"CADisplayLink.setFrameInterval", [NSString stringWithFormat:@"interval=%ld", (long)interval], NO);
    }
    if (PMDeviceSupports120Hz()) {
#if PM_ENABLE_DIAGNOSTIC_PROBES
        PMFPSFrameIntervalSetCount += 1;
        PMFPSLastEvent = @"CADisplayLink.setFrameInterval";
        PMFPSLastReason = PMFloatWindowConfirmed ? @"bannerActive" : @"global";
        PMFPSLastOrigInterval = interval;
        PMFPSLastAppliedInterval = 1;
        if (interval != 1) PMFPSOverriddenCount += 1;
#endif
        // Always apply 120Hz with highFrameRateReason
        if (PMIsTargetProcess()) {
            // SpringBoard
            if (PMIsEligibleNow()) {
                PMSetHighFrameRateReasonIfPossible(self, YES, NO);
            } else {
                PMSetHighFrameRateReasonDirect(self);
            }
        } else if (PMFloatIsEligibleNow() || PMIsAppEligibleNow()) {
            // Float or App (Float has higher priority in check order)
            PMSetHighFrameRateReasonDirect(self);
        }
        %orig(1);
    } else {
        %orig;
    }
}

%end

%hook CAAnimation

- (void)setPreferredFrameRateRange:(CAFrameRateRange)range {
    if (!PMIsTargetProcess()) {
        PMFloatAnimationRangeSetCount += 1;
        PMFloatLastAnimationClass = [PMClassName(self) copy];
        PMFloatRecordRange(@"CAAnimation.setPreferredFrameRateRange", range);
    }
    if (PMDeviceSupports120Hz()) {
        CAFrameRateRange appliedRange;
        if (PMIsTargetProcess()) {
            // SpringBoard: always apply 120Hz
            if (PMIsEligibleNow()) {
                PMSetHighFrameRateReasonIfPossible(self, NO, NO);
            } else {
                PMSetHighFrameRateReasonDirect(self);
            }
            appliedRange = PMForce120Range();
        } else if (PMFloatIsEligibleNow() || PMIsAppEligibleNow()) {
            // Float window or App process: apply 120Hz
            PMSetHighFrameRateReasonDirect(self);
            appliedRange = PMForce120Range();
        } else {
            // Fallback: should rarely reach here
            appliedRange = PMForce120Range();
        }
        %orig(appliedRange);
    } else {
        %orig;
    }
}

%end

@interface CAMetalLayer (Private)
@property (assign) NSUInteger maximumDrawableCount;
@end

%hook CAMetalLayer

- (NSUInteger)maximumDrawableCount {
    NSUInteger orig = %orig;
    if (PMDeviceSupports120Hz() && orig < 3) return 3;
    return orig;
}

%end

%hook CAMetalDrawable

- (void)presentAfterMinimumDuration:(CFTimeInterval)duration {
    if (PMDeviceSupports120Hz()) {
        %orig(1.0 / TARGET_FPS);
    } else {
        %orig;
    }
}

%end

%hook MTLCommandBuffer

- (void)presentDrawable:(id)drawable afterMinimumDuration:(CFTimeInterval)minimumDuration {
    if (PMDeviceSupports120Hz()) {
        %orig(drawable, 1.0 / TARGET_FPS);
    } else {
        %orig(drawable, minimumDuration);
    }
}

%end


%hook UIViewController

- (void)viewWillAppear:(BOOL)animated {
    if (!PMIsTargetProcess()) {
        // App processes: refresh persistent source on VC transitions
        PMAppRefreshPersistentSource();
        // SpringBoard: arm Float if floating window visible
        if (PMFloatAnyFloatingWindowVisible()) {
            PMFloatArm(@"vc.presentation");
        }
    }
    %orig;
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    // Re-affirm 120Hz after VC transitions in app processes
    if (!PMIsTargetProcess()) PMAppRefreshPersistentSource();
}

- (void)presentViewController:(UIViewController *)viewControllerToPresent animated:(BOOL)flag completion:(void (^)(void))completion {
    %orig;
    if (!PMIsTargetProcess()) PMAppRefreshPersistentSource();
}

%end

%hook UINavigationController

- (void)pushViewController:(UIViewController *)viewController animated:(BOOL)animated {
    %orig;
    if (!PMIsTargetProcess()) PMAppRefreshPersistentSource();
}

%end

%hook UICollectionView

- (void)reloadData {
#if !PM_ENABLE_DIAGNOSTIC_PROBES
    %orig;
    return;
#endif
    if (PMIsTargetProcess()) PMJankRecordListView((UIView *)self, @"UICollectionView.reloadData", YES);
    %orig;
}

- (void)layoutSubviews {
    %orig;
#if !PM_ENABLE_DIAGNOSTIC_PROBES
    return;
#endif
    if (PMIsTargetProcess()) PMJankRecordListView((UIView *)self, @"UICollectionView.layoutSubviews", NO);
}

%end

%hook UITableView

- (void)reloadData {
#if !PM_ENABLE_DIAGNOSTIC_PROBES
    %orig;
    return;
#endif
    if (PMIsTargetProcess()) PMJankRecordListView((UIView *)self, @"UITableView.reloadData", YES);
    %orig;
}

- (void)layoutSubviews {
    %orig;
    if (PMIsTargetProcess()) PMJankRecordListView((UIView *)self, @"UITableView.layoutSubviews", NO);
}

%end


%hook UIWindow

- (void)setFrame:(CGRect)frame {
#if !PM_ENABLE_DIAGNOSTIC_PROBES
    if (!PMIsTargetProcess()) {
        @try {
            if (PMFloatWindowLooksLikeStatusShrinkWindow((UIWindow *)self) && PMFloatRectLooksLikeCollapsedCapsule(frame) && PMFloatAnyFloatingWindowVisible()) {
                PMFloatPreArm(@"UIWindow.statusBar.smallFrame");
            }
            PMFloatArmForWindow((UIWindow *)self, @"UIWindow.setFrame");
        } @catch (__unused NSException *e) {}
    }
    %orig;
    return;
#endif
    if (!PMIsTargetProcess()) {
        PMFloatWindowSetFrameCount += 1;
        PMFloatLastWindowClass = [PMClassName(self) copy];
        PMFloatLastRootViewControllerClass = [PMClassName(self.rootViewController) copy];
        PMFloatLastFrame = frame;
        PMFloatWriteState(@"UIWindow.setFrame", PMFloatLastWindowClass ?: @"", NO);
        if (PMFloatWindowLooksLikeStatusShrinkWindow((UIWindow *)self) && PMFloatRectLooksLikeCollapsedCapsule(frame) && PMFloatAnyFloatingWindowVisible()) {
            PMFloatSmallStatusBarArmCount += 1;
            PMFloatPreArm(@"UIWindow.statusBar.smallFrame");
        }
        PMFloatArmForWindow((UIWindow *)self, @"UIWindow.setFrame");
    }
    %orig;
}

- (void)setBounds:(CGRect)bounds {
#if !PM_ENABLE_DIAGNOSTIC_PROBES
    if (!PMIsTargetProcess()) {
        @try { PMFloatArmForWindow((UIWindow *)self, @"UIWindow.setBounds"); } @catch (__unused NSException *e) {}
    }
    %orig;
    return;
#endif
    if (!PMIsTargetProcess()) {
        PMFloatWindowSetBoundsCount += 1;
        PMFloatLastWindowClass = [PMClassName(self) copy];
        PMFloatLastRootViewControllerClass = [PMClassName(self.rootViewController) copy];
        PMFloatLastBounds = bounds;
        PMFloatWriteState(@"UIWindow.setBounds", PMFloatLastWindowClass ?: @"", NO);
        PMFloatArmForWindow((UIWindow *)self, @"UIWindow.setBounds");
    }
    %orig;
}

- (void)makeKeyAndVisible {
    if (!PMIsTargetProcess()) {
        // In app processes: refresh persistent source on window activation
        PMAppRefreshPersistentSource();
        // In SpringBoard: arm Float for floating windows
        PMFloatArmForWindow((UIWindow *)self, @"window.makeKeyAndVisible");
    }
    %orig;
}

- (void)setWindowLevel:(UIWindowLevel)level {
    if (level >= 1000 && level < 2000 && !PMIsTargetProcess()) {
        NSString *winClass = PMClassName(self);
        PMFloatWriteState([NSString stringWithFormat:@"windowLevel=%.0f", (float)level], winClass ?: @"", YES);
        PMFloatArm(@"windowLevel.menu");
    }
    %orig;
}

%end

%hook UIView

- (void)setFrame:(CGRect)frame {
#if !PM_ENABLE_DIAGNOSTIC_PROBES
    if (!PMIsTargetProcess()) {
        @try {
            if (PMFloatWindowLooksLikeStatusShrinkWindow(((UIView *)self).window) && PMFloatRectLooksLikeCollapsedCapsule(frame) && PMFloatAnyFloatingWindowVisible()) {
                PMFloatPreArm(@"UIView.statusBar.smallFrame");
            }
            PMFloatArmForView((UIView *)self, @"UIView.setFrame");
        } @catch (__unused NSException *e) {}
    }
    %orig;
    return;
#endif
    if (PMIsTargetProcess()) PMJankRecordViewMutation((UIView *)self, @"UIView.setFrame", frame, NO);
    if (!PMIsTargetProcess()) {
        PMFloatViewSetFrameCount += 1;
        PMFloatLastViewClass = [PMClassName(self) copy];
        PMFloatLastFrame = frame;
        PMFloatCaptureWindowInfoForView(self);
        PMFloatWriteState(@"UIView.setFrame", PMFloatLastViewClass ?: @"", NO);
        @try {
            if (PMFloatWindowLooksLikeStatusShrinkWindow(((UIView *)self).window) && PMFloatRectLooksLikeCollapsedCapsule(frame) && PMFloatAnyFloatingWindowVisible()) {
                PMFloatSmallStatusBarArmCount += 1;
                PMFloatPreArm(@"UIView.statusBar.smallFrame");
            }
        } @catch (__unused NSException *e) {}
        PMFloatArmForView((UIView *)self, @"UIView.setFrame");
    }
    %orig;
}

- (void)setBounds:(CGRect)bounds {
#if !PM_ENABLE_DIAGNOSTIC_PROBES
    if (!PMIsTargetProcess()) {
        @try { PMFloatArmForView((UIView *)self, @"UIView.setBounds"); } @catch (__unused NSException *e) {}
    }
    %orig;
    return;
#endif
    if (PMIsTargetProcess()) PMJankRecordViewMutation((UIView *)self, @"UIView.setBounds", bounds, YES);
    if (!PMIsTargetProcess()) {
        PMFloatViewSetBoundsCount += 1;
        PMFloatLastViewClass = [PMClassName(self) copy];
        PMFloatLastBounds = bounds;
        PMFloatCaptureWindowInfoForView(self);
        PMFloatWriteState(@"UIView.setBounds", PMFloatLastViewClass ?: @"", NO);
        PMFloatArmForView((UIView *)self, @"UIView.setBounds");
    }
    %orig;
}

%end

%hook UIScrollView

- (void)setContentOffset:(CGPoint)contentOffset {
#if !PM_ENABLE_DIAGNOSTIC_PROBES
    if (PMIsTargetProcess()) {
        PMGlobalSBApply(@"UIScrollView.setContentOffset");
    } else {
        @try { PMAppScrollArm(@"UIScrollView.setContentOffset"); } @catch (__unused NSException *e) {}
    }
    %orig;
    return;
#endif
    if (PMIsTargetProcess()) {
        PMJankRecordScrollView((UIScrollView *)self, contentOffset);
        PMGlobalSBApply(@"UIScrollView.setContentOffset");
    }
    if (!PMIsTargetProcess()) PMAppScrollArm(@"UIScrollView.setContentOffset");
    %orig;
}

- (void)setContentOffset:(CGPoint)contentOffset animated:(BOOL)animated {
#if !PM_ENABLE_DIAGNOSTIC_PROBES
    if (PMIsTargetProcess()) {
        PMGlobalSBApply(@"UIScrollView.setContentOffsetAnimated");
    } else {
        @try { PMAppScrollArm(@"UIScrollView.setContentOffsetAnimated"); } @catch (__unused NSException *e) {}
    }
    %orig;
    return;
#endif
    if (PMIsTargetProcess()) {
        PMJankRecordScrollView((UIScrollView *)self, contentOffset);
        PMGlobalSBApply(@"UIScrollView.setContentOffsetAnimated");
    }
    if (!PMIsTargetProcess()) PMAppScrollArm(@"UIScrollView.setContentOffsetAnimated");
    %orig;
}

- (void)layoutSubviews {
#if !PM_ENABLE_DIAGNOSTIC_PROBES
    if (!PMIsTargetProcess()) {
        @try {
            if (PMAppScrollViewIsMoving((UIScrollView *)self)) PMAppScrollArm(@"UIScrollView.layoutSubviews.moving");
        } @catch (__unused NSException *e) {}
    }
    %orig;
    return;
#endif
    if (PMIsTargetProcess()) PMJankRecordListView((UIView *)self, @"UIScrollView.layoutSubviews", NO);
    if (!PMIsTargetProcess() && PMAppScrollViewIsMoving((UIScrollView *)self)) PMAppScrollArm(@"UIScrollView.layoutSubviews.moving");
    %orig;
}

%end

%hook UIViewPropertyAnimator

- (void)startAnimation {
#if !PM_ENABLE_DIAGNOSTIC_PROBES
    if (!PMIsTargetProcess()) PMAppRefreshPersistentSource();
    %orig;
    return;
#endif
    if (PMIsTargetProcess()) PMJankRecordPropertyAnimator(@"UIViewPropertyAnimator.startAnimation");
    %orig;
}

- (void)startAnimationAfterDelay:(NSTimeInterval)delay {
#if !PM_ENABLE_DIAGNOSTIC_PROBES
    %orig;
    return;
#endif
    if (PMIsTargetProcess()) PMJankRecordPropertyAnimator(@"UIViewPropertyAnimator.startAnimationAfterDelay");
    %orig;
}

%end

%hook CALayer

- (void)addAnimation:(CAAnimation *)animation forKey:(NSString *)key {
    if (PMIsEligibleNow() && animation && PMLayerBelongsToBannerWindow((CALayer *)self)) {
        PMApplyToCAObject(animation, NO, NO);
    }
#if !PM_ENABLE_DIAGNOSTIC_PROBES
    if (!PMIsTargetProcess()) {
        @try {
            NSString *floatKey = [key copy] ?: @"";
            if (PMFloatAnyFloatingWindowVisible() && ([floatKey isEqualToString:@"opacity"] || [floatKey containsString:@"position"] || [floatKey containsString:@"bounds"] || [floatKey containsString:@"transform"])) {
                PMFloatPreArm([NSString stringWithFormat:@"CALayer.addAnimation.%@", floatKey ?: @""]);
            }
            PMFloatArmForLayer((CALayer *)self, @"CALayer.addAnimation");
            if (PMFloatIsEligibleNow() && animation) PMApplyToCAObjectDirect(animation);
        } @catch (__unused NSException *e) {}
    }
    %orig;
    return;
#endif
    if (PMIsTargetProcess()) PMJankRecordLayerAnimation((CALayer *)self, animation, key);
    if (!PMIsTargetProcess()) {
        PMFloatLayerAddAnimationCount += 1;
        PMFloatLastLayerClass = [PMClassName(self) copy];
        PMFloatLastAnimationClass = [PMClassName(animation) copy];
        PMFloatLastAnimationKey = [key copy] ?: @"";
        PMFloatWriteState(@"CALayer.addAnimation", PMFloatLastAnimationKey ?: @"", NO);
        if (PMFloatAnyFloatingWindowVisible() && ([PMFloatLastAnimationKey isEqualToString:@"opacity"] || [PMFloatLastAnimationKey containsString:@"position"] || [PMFloatLastAnimationKey containsString:@"bounds"] || [PMFloatLastAnimationKey containsString:@"transform"])) {
            PMFloatPreArm([NSString stringWithFormat:@"CALayer.addAnimation.%@", PMFloatLastAnimationKey ?: @""]);
        }
        PMFloatArmForLayer((CALayer *)self, @"CALayer.addAnimation");
        if (PMFloatIsEligibleNow() && animation) PMApplyToCAObjectDirect(animation);
    }
    %orig;
}

- (void)setBounds:(CGRect)bounds {
#if !PM_ENABLE_DIAGNOSTIC_PROBES
    if (!PMIsTargetProcess()) {
        @try { PMFloatArmForLayer((CALayer *)self, @"CALayer.setBounds"); } @catch (__unused NSException *e) {}
    }
    %orig;
    return;
#endif
    if (PMIsTargetProcess()) PMJankRecordLayerMutation((CALayer *)self, @"CALayer.setBounds");
    if (!PMIsTargetProcess()) {
        PMFloatLayerSetBoundsCount += 1;
        PMFloatLastLayerClass = [PMClassName(self) copy];
        PMFloatLastBounds = bounds;
        PMFloatWriteState(@"CALayer.setBounds", PMFloatLastLayerClass ?: @"", NO);
        PMFloatArmForLayer((CALayer *)self, @"CALayer.setBounds");
    }
    %orig;
}

- (void)setPosition:(CGPoint)position {
#if !PM_ENABLE_DIAGNOSTIC_PROBES
    if (!PMIsTargetProcess()) {
        @try { PMFloatArmForLayer((CALayer *)self, @"CALayer.setPosition"); } @catch (__unused NSException *e) {}
    }
    %orig;
    return;
#endif
    if (PMIsTargetProcess()) PMJankRecordLayerMutation((CALayer *)self, @"CALayer.setPosition");
    if (!PMIsTargetProcess()) {
        PMFloatLayerSetPositionCount += 1;
        PMFloatLastLayerClass = [PMClassName(self) copy];
        PMFloatLastPosition = position;
        PMFloatWriteState(@"CALayer.setPosition", PMFloatLastLayerClass ?: @"", NO);
        PMFloatArmForLayer((CALayer *)self, @"CALayer.setPosition");
    }
    %orig;
}

- (void)setTransform:(CATransform3D)transform {
#if !PM_ENABLE_DIAGNOSTIC_PROBES
    if (!PMIsTargetProcess()) {
        @try { PMFloatArmForLayer((CALayer *)self, @"CALayer.setTransform"); } @catch (__unused NSException *e) {}
    }
    %orig;
    return;
#endif
    if (PMIsTargetProcess()) PMJankRecordLayerMutation((CALayer *)self, @"CALayer.setTransform");
    if (!PMIsTargetProcess()) {
        PMFloatLayerSetTransformCount += 1;
        PMFloatLastLayerClass = [PMClassName(self) copy];
        PMFloatWriteState(@"CALayer.setTransform", PMFloatLastLayerClass ?: @"", NO);
        PMFloatArmForLayer((CALayer *)self, @"CALayer.setTransform");
    }
    %orig;
}

%end


// ========== BROAD MENU / MODAL / OVERLAY DETECTION ==========
// Strategy: detect menus/modals via UIWindow lifecycle + view hierarchy clues
// without relying on specific class names.

// makeKeyAndVisible and setWindowLevel merged into main %hook UIWindow block above

// Catch alert/modal presentations
%hook UIAlertController
- (void)viewDidAppear:(BOOL)animated {
    if (!PMIsTargetProcess()) {
        PMAppRefreshPersistentSource();
        PMFloatArm(@"alert.viewDidAppear");
    }
    %orig;
}
%end

// Catch UIMenuController (classic menu)
%hook UIMenuController
- (void)showFromRect:(CGRect)rect inView:(UIView *)view animated:(BOOL)animated {
    if (!PMIsTargetProcess()) {
        PMFloatWriteState(@"menu.showFromRect", PMClassName(view), YES);
        PMFloatArm(@"menu.showFromRect");
    }
    %orig;
}
- (void)showFromBarButtonItem:(id)item animated:(BOOL)animated {
    if (!PMIsTargetProcess()) {
        PMFloatWriteState(@"menu.showFromBarButton", PMClassName(item), YES);
        PMFloatArm(@"menu.showFromBarButton");
    }
    %orig;
}
%end

// Catch UIPopoverPresentationController
%hook UIPopoverPresentationController
- (void)viewDidAppear:(BOOL)animated {
    if (!PMIsTargetProcess()) {
        PMFloatWriteState(@"popover.viewDidAppear", PMClassName(self), YES);
        PMFloatArm(@"popover.viewDidAppear");
    }
    %orig;
}
%end

// Runtime hook for UIContextMenuInteraction (iOS 14+)
static void PMHookContextMenuInteractionIfAvailable(void) {
    Class cls = NSClassFromString(@"UIContextMenuInteraction");
    if (!cls) return;
    SEL sel = NSSelectorFromString(@"_presentMenuAtLocation:");
    if (![cls instancesRespondToSelector:sel]) return;
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) return;
    IMP origImp = method_getImplementation(m);
    IMP newImp = imp_implementationWithBlock(^(id self, CGPoint p) {
        if (!PMIsTargetProcess()) {
            PMFloatWriteState(@"ctxMenu.present", @"UIContextMenuInteraction", YES);
            PMFloatArm(@"ctxMenu.present");
        }
        ((void(*)(id,SEL,CGPoint))origImp)(self, sel, p);
    });
    method_setImplementation(m, newImp);
}

// Runtime hook for UIEditMenuInteraction (iOS 16+)
static void PMHookEditMenuInteractionIfAvailable(void) {
    Class cls = NSClassFromString(@"UIEditMenuInteraction");
    if (!cls) return;
    SEL sel = NSSelectorFromString(@"_presentMenuAtLocation:");
    if (![cls instancesRespondToSelector:sel]) return;
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) return;
    IMP origImp = method_getImplementation(m);
    IMP newImp = imp_implementationWithBlock(^(id self, CGPoint p) {
        if (!PMIsTargetProcess()) {
            PMFloatWriteState(@"editMenu.present", @"UIEditMenuInteraction", YES);
            PMFloatArm(@"editMenu.present");
        }
        ((void(*)(id,SEL,CGPoint))origImp)(self, sel, p);
    });
    method_setImplementation(m, newImp);
}

// ========== END MENU / MODAL / OVERLAY DETECTION ==========

typedef void (*PMObjIMP)(id, SEL, id);
typedef void (*PMObjIntIMP)(id, SEL, id, NSInteger);
typedef void (*PMVoidIMP)(id, SEL);
typedef void (*PMRangeSetterIMP)(id, SEL, CAFrameRateRange);
typedef void (*PMIntSetterIMP)(id, SEL, NSInteger);
typedef id (*PMClassDLFactoryIMP)(id, SEL, id, SEL);
typedef void (*PMReasonsSetterIMP)(id, SEL, const unsigned int *, NSUInteger);
typedef void (*PMUIntSetterIMP)(id, SEL, unsigned int);

static PMObjIMP orig_SBNotificationBannerDestination_presentableWillAppearAsBanner = NULL;
static PMObjIMP orig_SBNotificationBannerDestination_presentableDidAppearAsBanner = NULL;
static PMObjIntIMP orig_SBNotificationBannerDestination_presentableWillDisappearAsBanner = NULL;
static PMObjIntIMP orig_SBNotificationBannerDestination_presentableDidDisappearAsBanner = NULL;
static PMObjIntIMP orig_SBNotificationBannerDestination_presentableWillNotAppearAsBanner = NULL;
static PMObjIMP orig_NCNotificationPresentableViewController_presentableWillAppearAsBanner = NULL;
static PMObjIMP orig_NCNotificationPresentableViewController_presentableDidAppearAsBanner = NULL;
static PMObjIntIMP orig_NCNotificationPresentableViewController_presentableWillDisappearAsBanner = NULL;
static PMObjIntIMP orig_NCNotificationPresentableViewController_presentableDidDisappearAsBanner = NULL;
static PMObjIntIMP orig_NCNotificationPresentableViewController_presentableWillNotAppearAsBanner = NULL;
static PMVoidIMP orig_NCNotificationShortLookView_didMoveToWindow = NULL;
static PMRangeSetterIMP orig_CADynamicFrameRateSource_setPreferredFrameRateRange = NULL;
// orig_CADynamicFrameRateSource_setHighFrameRateReasons_count: forward-declared earlier (line ~1665)

static BOOL PMInstallHookIfExists(const char *className, SEL selector, IMP replacement, IMP *original) {
    Class cls = objc_getClass(className);
    if (!cls || !class_getInstanceMethod(cls, selector)) return NO;
    MSHookMessageEx(cls, selector, replacement, original);
    return YES;
}

static void repl_SBNotificationBannerDestination_presentableWillAppearAsBanner(id self, SEL _cmd, id presentable) {
    PMBeginBannerSession(@"SBNotificationBannerDestination.presentableWillAppearAsBanner", presentable);
    if (orig_SBNotificationBannerDestination_presentableWillAppearAsBanner) orig_SBNotificationBannerDestination_presentableWillAppearAsBanner(self, _cmd, presentable);
    PMScheduleCapture(presentable, @"SBNotificationBannerDestination.afterWillAppear");
}

static void repl_SBNotificationBannerDestination_presentableDidAppearAsBanner(id self, SEL _cmd, id presentable) {
    if (orig_SBNotificationBannerDestination_presentableDidAppearAsBanner) orig_SBNotificationBannerDestination_presentableDidAppearAsBanner(self, _cmd, presentable);
    PMScheduleCapture(presentable, @"SBNotificationBannerDestination.didAppear");
}

static void repl_SBNotificationBannerDestination_presentableWillDisappearAsBanner(id self, SEL _cmd, id presentable, NSInteger reason) {
    PMExtendExitTailAndApply(@"SBNotificationBannerDestination.willDisappear.exitTailApply");
    if (orig_SBNotificationBannerDestination_presentableWillDisappearAsBanner) orig_SBNotificationBannerDestination_presentableWillDisappearAsBanner(self, _cmd, presentable, reason);
}

static void repl_SBNotificationBannerDestination_presentableDidDisappearAsBanner(id self, SEL _cmd, id presentable, NSInteger reason) {
    if (orig_SBNotificationBannerDestination_presentableDidDisappearAsBanner) orig_SBNotificationBannerDestination_presentableDidDisappearAsBanner(self, _cmd, presentable, reason);
    PMEndBannerSession(@"SBNotificationBannerDestination.presentableDidDisappearAsBanner", @"", presentable);
}

static void repl_SBNotificationBannerDestination_presentableWillNotAppearAsBanner(id self, SEL _cmd, id presentable, NSInteger reason) {
    if (orig_SBNotificationBannerDestination_presentableWillNotAppearAsBanner) orig_SBNotificationBannerDestination_presentableWillNotAppearAsBanner(self, _cmd, presentable, reason);
    PMEndBannerSession(@"SBNotificationBannerDestination.presentableWillNotAppearAsBanner", @"", presentable);
}

static void repl_NCNotificationPresentableViewController_presentableWillAppearAsBanner(id self, SEL _cmd, id presentable) {
    PMBeginBannerSession(@"NCNotificationPresentableViewController.presentableWillAppearAsBanner", presentable ?: self);
    if (orig_NCNotificationPresentableViewController_presentableWillAppearAsBanner) orig_NCNotificationPresentableViewController_presentableWillAppearAsBanner(self, _cmd, presentable);
    PMScheduleCapture(presentable ?: self, @"NCNotificationPresentableViewController.afterWillAppear");
}

static void repl_NCNotificationPresentableViewController_presentableDidAppearAsBanner(id self, SEL _cmd, id presentable) {
    if (orig_NCNotificationPresentableViewController_presentableDidAppearAsBanner) orig_NCNotificationPresentableViewController_presentableDidAppearAsBanner(self, _cmd, presentable);
    PMScheduleCapture(presentable ?: self, @"NCNotificationPresentableViewController.didAppear");
}

static void repl_NCNotificationPresentableViewController_presentableWillDisappearAsBanner(id self, SEL _cmd, id presentable, NSInteger reason) {
    PMExtendExitTailAndApply(@"NCNotificationPresentableViewController.willDisappear.exitTailApply");
    if (orig_NCNotificationPresentableViewController_presentableWillDisappearAsBanner) orig_NCNotificationPresentableViewController_presentableWillDisappearAsBanner(self, _cmd, presentable, reason);
}

static void repl_NCNotificationPresentableViewController_presentableDidDisappearAsBanner(id self, SEL _cmd, id presentable, NSInteger reason) {
    if (orig_NCNotificationPresentableViewController_presentableDidDisappearAsBanner) orig_NCNotificationPresentableViewController_presentableDidDisappearAsBanner(self, _cmd, presentable, reason);
    PMEndBannerSession(@"NCNotificationPresentableViewController.presentableDidDisappearAsBanner", @"", presentable ?: self);
}

static void repl_NCNotificationPresentableViewController_presentableWillNotAppearAsBanner(id self, SEL _cmd, id presentable, NSInteger reason) {
    if (orig_NCNotificationPresentableViewController_presentableWillNotAppearAsBanner) orig_NCNotificationPresentableViewController_presentableWillNotAppearAsBanner(self, _cmd, presentable, reason);
    PMEndBannerSession(@"NCNotificationPresentableViewController.presentableWillNotAppearAsBanner", @"", presentable ?: self);
}

static void repl_NCNotificationShortLookView_didMoveToWindow(id self, SEL _cmd) {
    if (orig_NCNotificationShortLookView_didMoveToWindow) orig_NCNotificationShortLookView_didMoveToWindow(self, _cmd);
    PMCaptureWindowFromView(self, @"NCNotificationShortLookView.didMoveToWindow");
}

// Forward declaration for repl hook
static void PMFPSRecordRange(NSString *event, NSString *reason, CAFrameRateRange origRange, CAFrameRateRange appliedRange);

static void repl_CADynamicFrameRateSource_setPreferredFrameRateRange(id self, SEL _cmd, CAFrameRateRange range) {
    CAFrameRateRange appliedRange = range;
    // Always force 120Hz on our persistent sources
    if (PMIsManagedSource(self)) {
        appliedRange = PMForce120Range();
    } else if (PMIsEligibleNow() || PMFloatIsEligibleNow()) {
        if (PMIsEligibleNow()) PMSetHighFrameRateReasonIfPossible(self, NO, YES);
        if (PMFloatIsEligibleNow() || PMIsAppEligibleNow()) PMSetHighFrameRateReasonDirect(self);
        appliedRange = PMForce120Range();
    }
    PMFPSRecordRange(@"CADynamicFrameRateSource.setPreferredFrameRateRange", @"dynamicSource", range, appliedRange);
    if (orig_CADynamicFrameRateSource_setPreferredFrameRateRange) orig_CADynamicFrameRateSource_setPreferredFrameRateRange(self, _cmd, appliedRange);
}

static void repl_CADynamicFrameRateSource_setHighFrameRateReasons_count(id self, SEL _cmd, const unsigned int *reasons, NSUInteger count) {
    if (!orig_CADynamicFrameRateSource_setHighFrameRateReasons_count) return;

    // Preserve Apple's clear/release path for non-persistent sources.
    // But protect our persistent sources (SB global + App persistent) from
    // being cleared by system animation cleanup.
    if (!reasons || count == 0) {
        if (PMIsManagedSource(self)) {
            // Don't clear our persistent sources — re-apply instead
            unsigned int persistReasons[1] = { 1U };
            orig_CADynamicFrameRateSource_setHighFrameRateReasons_count(self, _cmd, persistReasons, (NSUInteger)1);
            return;
        }
        orig_CADynamicFrameRateSource_setHighFrameRateReasons_count(self, _cmd, reasons, count);
        return;
    }

    if (PMIsEligibleNow() || PMFloatIsEligibleNow() || PMIsAppEligibleNow()) {
        unsigned int forced[1] = { 1U };
        orig_CADynamicFrameRateSource_setHighFrameRateReasons_count(self, _cmd, forced, 1);
    } else {
        orig_CADynamicFrameRateSource_setHighFrameRateReasons_count(self, _cmd, reasons, count);
    }
}

static void PMInstallHooks(void) {
    if (!PMIsTargetProcess()) return;
    PMInstallHookIfExists("SBNotificationBannerDestination", @selector(presentableWillAppearAsBanner:), (IMP)repl_SBNotificationBannerDestination_presentableWillAppearAsBanner, (IMP *)&orig_SBNotificationBannerDestination_presentableWillAppearAsBanner);
    PMInstallHookIfExists("SBNotificationBannerDestination", @selector(presentableDidAppearAsBanner:), (IMP)repl_SBNotificationBannerDestination_presentableDidAppearAsBanner, (IMP *)&orig_SBNotificationBannerDestination_presentableDidAppearAsBanner);
    PMInstallHookIfExists("SBNotificationBannerDestination", @selector(presentableWillDisappearAsBanner:withReason:), (IMP)repl_SBNotificationBannerDestination_presentableWillDisappearAsBanner, (IMP *)&orig_SBNotificationBannerDestination_presentableWillDisappearAsBanner);
    PMInstallHookIfExists("SBNotificationBannerDestination", @selector(presentableDidDisappearAsBanner:withReason:), (IMP)repl_SBNotificationBannerDestination_presentableDidDisappearAsBanner, (IMP *)&orig_SBNotificationBannerDestination_presentableDidDisappearAsBanner);
    PMInstallHookIfExists("SBNotificationBannerDestination", @selector(presentableWillNotAppearAsBanner:withReason:), (IMP)repl_SBNotificationBannerDestination_presentableWillNotAppearAsBanner, (IMP *)&orig_SBNotificationBannerDestination_presentableWillNotAppearAsBanner);

    PMInstallHookIfExists("NCNotificationPresentableViewController", @selector(presentableWillAppearAsBanner:), (IMP)repl_NCNotificationPresentableViewController_presentableWillAppearAsBanner, (IMP *)&orig_NCNotificationPresentableViewController_presentableWillAppearAsBanner);
    PMInstallHookIfExists("NCNotificationPresentableViewController", @selector(presentableDidAppearAsBanner:), (IMP)repl_NCNotificationPresentableViewController_presentableDidAppearAsBanner, (IMP *)&orig_NCNotificationPresentableViewController_presentableDidAppearAsBanner);
    PMInstallHookIfExists("NCNotificationPresentableViewController", @selector(presentableWillDisappearAsBanner:withReason:), (IMP)repl_NCNotificationPresentableViewController_presentableWillDisappearAsBanner, (IMP *)&orig_NCNotificationPresentableViewController_presentableWillDisappearAsBanner);
    PMInstallHookIfExists("NCNotificationPresentableViewController", @selector(presentableDidDisappearAsBanner:withReason:), (IMP)repl_NCNotificationPresentableViewController_presentableDidDisappearAsBanner, (IMP *)&orig_NCNotificationPresentableViewController_presentableDidDisappearAsBanner);
    PMInstallHookIfExists("NCNotificationPresentableViewController", @selector(presentableWillNotAppearAsBanner:withReason:), (IMP)repl_NCNotificationPresentableViewController_presentableWillNotAppearAsBanner, (IMP *)&orig_NCNotificationPresentableViewController_presentableWillNotAppearAsBanner);
    PMInstallHookIfExists("NCNotificationShortLookView", @selector(didMoveToWindow), (IMP)repl_NCNotificationShortLookView_didMoveToWindow, (IMP *)&orig_NCNotificationShortLookView_didMoveToWindow);

}

// Install CADynamicFrameRateSource hooks in ALL UIKit processes (not just SpringBoard).
// Protects managed sources from system clearing in both SB and app processes.
static void PMInstallDynamicSourceHooks(void) {
    PMInstallHookIfExists("CADynamicFrameRateSource", NSSelectorFromString(@"setPreferredFrameRateRange:"), (IMP)repl_CADynamicFrameRateSource_setPreferredFrameRateRange, (IMP *)&orig_CADynamicFrameRateSource_setPreferredFrameRateRange);
    PMInstallHookIfExists("CADynamicFrameRateSource", NSSelectorFromString(@"setHighFrameRateReasons:count:"), (IMP)repl_CADynamicFrameRateSource_setHighFrameRateReasons_count, (IMP *)&orig_CADynamicFrameRateSource_setHighFrameRateReasons_count);
}

%ctor {
    @autoreleasepool {
        if (PMDeviceSupports120Hz()) {
            %init;
            // Dynamic source protection for ALL processes
            PMInstallDynamicSourceHooks();
            if (PMIsTargetProcess()) {
                PMInstallHooks();
                PMHookContextMenuInteractionIfAvailable();
                PMHookEditMenuInteractionIfAvailable();
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.50 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    PMGlobalSBSetup();
                });
            }
            if (!PMIsTargetProcess()) {
                PMFloatProbeInjectedCount += 1;
                // Initialize persistent 120Hz source after main display is ready
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.50 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    PMAppEnsurePersistentSource();
                });
                // Re-apply when app returns from background
                [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(__unused NSNotification *note) {
                    PMAppRefreshPersistentSource();
                }];
            }
        }
    }
}
