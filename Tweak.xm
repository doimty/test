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

static NSString *PMBundleID(void) {
    static NSString *bundleID = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        bundleID = [[[NSBundle mainBundle] bundleIdentifier] copy] ?: @"";
    });
    return bundleID;
}

static BOOL PMIsTargetProcess(void) {
    return [PMBundleID() isEqualToString:@"com.apple.springboard"];
}

static BOOL PMIsArmed(void) {
    return CFAbsoluteTimeGetCurrent() < PMBannerArmUntil;
}

static BOOL PMIsEligibleNow(void) {
    return PMIsTargetProcess() && PMBannerWindowConfirmed && PMIsArmed();
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
    range.minimum = 80;
    range.preferred = TARGET_FPS;
    range.maximum = TARGET_FPS;
    return range;
}

static CAFrameRateRange PMGlobal120RangeFromRange(CAFrameRateRange range) {
    CAFrameRateRange newRange;
    newRange.minimum = (range.minimum > 0 && range.minimum <= TARGET_FPS) ? range.minimum : 10;
    newRange.preferred = TARGET_FPS;
    newRange.maximum = TARGET_FPS;
    if (newRange.minimum > TARGET_FPS) newRange.minimum = 10;
    return newRange;
}

typedef void (*PMRangeSetterDyn)(id, SEL, CAFrameRateRange);
typedef void (*PMUIntSetterDyn)(id, SEL, unsigned int);
typedef void (*PMReasonsSetterDyn)(id, SEL, const unsigned int *, NSUInteger);

static void PMSetHighFrameRateReasonIfPossible(id obj, BOOL isDisplayLink, BOOL isDynamicSource) {
    if (!obj || !PMIsEligibleNow()) return;
    @try {
        SEL singleSel = NSSelectorFromString(@"setHighFrameRateReason:");
        if ([obj respondsToSelector:singleSel]) {
            PMUIntSetterDyn fn = (PMUIntSetterDyn)objc_msgSend;
            fn(obj, singleSel, 1U);
        }
        SEL multiSel = NSSelectorFromString(@"setHighFrameRateReasons:count:");
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
        SEL sel = NSSelectorFromString(@"setPreferredFrameRateRange:");
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

static id PMMainCADisplay(void) {
    Class CADisplayClass = NSClassFromString(@"CADisplay");
    if (!CADisplayClass || ![CADisplayClass respondsToSelector:@selector(mainDisplay)]) return nil;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    id display = [CADisplayClass performSelector:@selector(mainDisplay)];
#pragma clang diagnostic pop
    return display;
}

static void PMApplyDisplayFrameRateSource(NSString *source) {
    if (!PMIsEligibleNow()) return;
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

@interface SBLowPowerModeController : NSObject
+ (instancetype)sharedInstance;
- (BOOL)isInLowPowerMode;
@end

@interface _CDBatterySaver : NSObject
+ (id)batterySaver;
- (NSInteger)getPowerMode;
@end

%hook SBLowPowerModeController

- (BOOL)isInLowPowerMode {
    return NO;
}

%end

%hook _CDBatterySaver

- (NSInteger)getPowerMode {
    return 0;
}

%end

%hook NSProcessInfo

- (BOOL)isLowPowerModeEnabled {
    return NO;
}

%end

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
    if (PMDeviceSupports120Hz() && link) {
        if (PMIsEligibleNow()) {
            PMApplyToCAObject(link, YES, NO);
        } else if ([link respondsToSelector:@selector(setPreferredFrameRateRange:)]) {
            CAFrameRateRange range;
            range.minimum = 10;
            range.preferred = TARGET_FPS;
            range.maximum = TARGET_FPS;
            [link setPreferredFrameRateRange:range];
        } else if ([link respondsToSelector:@selector(setPreferredFramesPerSecond:)]) {
            [link setPreferredFramesPerSecond:0];
        }
    }
    return link;
}

- (void)setPreferredFrameRateRange:(CAFrameRateRange)range {
    if (PMDeviceSupports120Hz()) {
        if (PMIsEligibleNow()) {
            PMSetHighFrameRateReasonIfPossible(self, YES, NO);
            %orig(PMForce120Range());
        } else {
            %orig(PMGlobal120RangeFromRange(range));
        }
    } else {
        %orig;
    }
}

- (void)setPreferredFramesPerSecond:(NSInteger)fps {
    if (PMDeviceSupports120Hz()) {
        if (PMIsEligibleNow()) PMSetHighFrameRateReasonIfPossible(self, YES, NO);
        %orig(PMIsEligibleNow() ? TARGET_FPS : 0);
    } else {
        %orig;
    }
}

- (void)setFrameInterval:(NSInteger)interval {
    if (PMDeviceSupports120Hz()) {
        if (PMIsEligibleNow()) PMSetHighFrameRateReasonIfPossible(self, YES, NO);
        %orig(1);
    } else {
        %orig;
    }
}

%end

%hook CAAnimation

- (void)setPreferredFrameRateRange:(CAFrameRateRange)range {
    if (PMDeviceSupports120Hz()) {
        if (PMIsEligibleNow()) {
            PMSetHighFrameRateReasonIfPossible(self, NO, NO);
            %orig(PMForce120Range());
        } else {
            %orig(PMGlobal120RangeFromRange(range));
        }
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

typedef void (*PMObjIMP)(id, SEL, id);
typedef void (*PMObjIntIMP)(id, SEL, id, NSInteger);
typedef void (*PMVoidIMP)(id, SEL);
typedef void (*PMRangeSetterIMP)(id, SEL, CAFrameRateRange);
typedef void (*PMIntSetterIMP)(id, SEL, NSInteger);
typedef id (*PMClassDLFactoryIMP)(id, SEL, id, SEL);
typedef void (*PMReasonsSetterIMP)(id, SEL, const unsigned int *, NSUInteger);
typedef void (*PMUIntSetterIMP)(id, SEL, unsigned int);
typedef void (*PMLayerAddAnimationIMP)(id, SEL, CAAnimation *, NSString *);

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
static PMReasonsSetterIMP orig_CADynamicFrameRateSource_setHighFrameRateReasons_count = NULL;
static PMLayerAddAnimationIMP orig_CALayer_addAnimation_forKey = NULL;

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

static void repl_CADynamicFrameRateSource_setPreferredFrameRateRange(id self, SEL _cmd, CAFrameRateRange range) {
    if (PMIsEligibleNow()) {
        PMSetHighFrameRateReasonIfPossible(self, NO, YES);
        if (orig_CADynamicFrameRateSource_setPreferredFrameRateRange) orig_CADynamicFrameRateSource_setPreferredFrameRateRange(self, _cmd, PMForce120Range());
    } else if (orig_CADynamicFrameRateSource_setPreferredFrameRateRange) {
        orig_CADynamicFrameRateSource_setPreferredFrameRateRange(self, _cmd, range);
    }
}

static void repl_CADynamicFrameRateSource_setHighFrameRateReasons_count(id self, SEL _cmd, const unsigned int *reasons, NSUInteger count) {
    if (!orig_CADynamicFrameRateSource_setHighFrameRateReasons_count) return;

    // Preserve Apple's clear/release path. UIKit/QuartzCore can pass NULL/0
    // while removing in-process animation entries; forcing {1} there may
    // corrupt CADynamicFrameRateSource internal reason lifetime.
    if (!reasons || count == 0) {
        orig_CADynamicFrameRateSource_setHighFrameRateReasons_count(self, _cmd, reasons, count);
        return;
    }

    if (PMIsEligibleNow()) {
        unsigned int forced[1] = { 1U };
        orig_CADynamicFrameRateSource_setHighFrameRateReasons_count(self, _cmd, forced, 1);
    } else {
        orig_CADynamicFrameRateSource_setHighFrameRateReasons_count(self, _cmd, reasons, count);
    }
}

static void repl_CALayer_addAnimation_forKey(id self, SEL _cmd, CAAnimation *animation, NSString *key) {
    if (PMIsEligibleNow() && animation && PMLayerBelongsToBannerWindow((CALayer *)self)) {
        PMApplyToCAObject(animation, NO, NO);
    }
    if (orig_CALayer_addAnimation_forKey) orig_CALayer_addAnimation_forKey(self, _cmd, animation, key);
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

    PMInstallHookIfExists("CADynamicFrameRateSource", NSSelectorFromString(@"setPreferredFrameRateRange:"), (IMP)repl_CADynamicFrameRateSource_setPreferredFrameRateRange, (IMP *)&orig_CADynamicFrameRateSource_setPreferredFrameRateRange);
    PMInstallHookIfExists("CADynamicFrameRateSource", NSSelectorFromString(@"setHighFrameRateReasons:count:"), (IMP)repl_CADynamicFrameRateSource_setHighFrameRateReasons_count, (IMP *)&orig_CADynamicFrameRateSource_setHighFrameRateReasons_count);
    PMInstallHookIfExists("CALayer", @selector(addAnimation:forKey:), (IMP)repl_CALayer_addAnimation_forKey, (IMP *)&orig_CALayer_addAnimation_forKey);
}

%ctor {
    @autoreleasepool {
        if (PMDeviceSupports120Hz()) {
            %init;
            if (PMIsTargetProcess()) {
                PMInstallHooks();
            }
        }
    }
}
