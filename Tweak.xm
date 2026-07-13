#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
#import <dispatch/dispatch.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <substrate.h>
#import <rootless.h>
#import <Metal/Metal.h>
#include <notify.h>

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
static CFAbsoluteTime PMBannerLastSourceApplyAt = 0;

// Utility functions (shared across all modules).
#include "src/PMUtility.xm.inc"


// Banner lifecycle (depends on PMUtility for PMIsTargetProcess, etc.).
#include "src/PMBanner.xm.inc"

// Diagnostics (disabled by PM_ENABLE_DIAGNOSTIC_PROBES 0).
#include "src/PMDiagnostic.xm.inc"

static BOOL PMFloatWindowConfirmed = NO;
static id PMGlobalSBDisplaySource = nil;
static NSUInteger PMGlobalSBCreateCount = 0;
static NSUInteger PMGlobalSBApplyCount = 0;
static BOOL PMGlobalSBEnabled = NO;
static CFAbsoluteTime PMGlobalLastApply = 0;

// Keepalive for injection-blocked foreground apps.
#include "src/PMKeepAlive.xm.inc"

// Floating-window/menu support.
#include "src/PMFloat.xm.inc"

// App-process persistent DynamicSource owner.
#include "src/PMAppPersistent.xm.inc"

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

// Broaden refresh-rate controller surface. maximum alone is not enough when
// DPPMS negotiates active rate against blocked-app scroll cadence.
- (long long)maximumRefreshRate {
    return TARGET_FPS;
}

- (long long)defaultRefreshRate {
    return TARGET_FPS;
}

- (long long)activeRefreshRate {
    return TARGET_FPS;
}

- (void)setActiveRefreshRate:(long long)rate {
    %orig((long long)TARGET_FPS);
}

%end

%hook UIScreen

- (NSInteger)maximumFramesPerSecond {
    if (PMDeviceSupports120Hz()) return TARGET_FPS;
    return %orig;
}

%end

%hook CADisplayLink

// Hot path: no fake SB/Float/App branches. If device supports 120Hz, force it.
// Eligibility only gates DynamicSource lifecycle elsewhere, not per-link apply.

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
        PMApplyToCAObjectDirect(link);
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
        PMSetHighFrameRateReasonDirect(self);
        %orig(PMForce120Range());
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
        PMFPSLastReason = @"force120";
        PMFPSLastOrigFPS = fps;
        PMFPSLastAppliedFPS = TARGET_FPS;
        if (fps != TARGET_FPS) PMFPSOverriddenCount += 1;
#endif
        PMSetHighFrameRateReasonDirect(self);
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
        PMFPSLastReason = @"force120";
        PMFPSLastOrigInterval = interval;
        PMFPSLastAppliedInterval = 1;
        if (interval != 1) PMFPSOverriddenCount += 1;
#endif
        PMSetHighFrameRateReasonDirect(self);
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
        PMSetHighFrameRateReasonDirect(self);
        %orig(PMForce120Range());
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
        // App process only (this branch is !SpringBoard).
        PMAppRefreshPersistentSource();
        // Float arm is no-op unless floating package/window is present.
        PMFloatArmForWindow((UIWindow *)self, @"window.makeKeyAndVisible");
    }
    %orig;
}

- (void)setWindowLevel:(UIWindowLevel)level {
    if (level >= 1000 && level < 2000 && !PMIsTargetProcess()) {
        NSString *winClass = PMClassName(self);
        PMFloatWriteState([NSString stringWithFormat:@"windowLevel=%.0f", (float)level], winClass ?: @"", YES);
        PMAppRefreshPersistentSource();
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
// Ordinary apps: only refresh App persistent source.
// Float arm is gated internally (floating package / floating window only).
%hook UIAlertController
- (void)viewDidAppear:(BOOL)animated {
    if (!PMIsTargetProcess()) {
        // Ordinary apps: refresh App persistent only.
        // Float arm lives on window/float-feature paths, not generic menus.
        PMAppRefreshPersistentSource();
    }
    %orig;
}
%end

// Catch UIMenuController (classic menu)
%hook UIMenuController
- (void)showFromRect:(CGRect)rect inView:(UIView *)view animated:(BOOL)animated {
    if (!PMIsTargetProcess()) PMAppRefreshPersistentSource();
    %orig;
}
- (void)showFromBarButtonItem:(id)item animated:(BOOL)animated {
    if (!PMIsTargetProcess()) PMAppRefreshPersistentSource();
    %orig;
}
%end

// Catch UIPopoverPresentationController
%hook UIPopoverPresentationController
- (void)viewDidAppear:(BOOL)animated {
    if (!PMIsTargetProcess()) PMAppRefreshPersistentSource();
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
        if (!PMIsTargetProcess()) PMAppRefreshPersistentSource();
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
        if (!PMIsTargetProcess()) PMAppRefreshPersistentSource();
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
        if (PMFloatIsEligibleNow() || PMIsAppProcessEligible()) PMSetHighFrameRateReasonDirect(self);
        appliedRange = PMForce120Range();
    }
    PMFPSRecordRange(@"CADynamicFrameRateSource.setPreferredFrameRateRange", @"dynamicSource", range, appliedRange);
    if (orig_CADynamicFrameRateSource_setPreferredFrameRateRange) orig_CADynamicFrameRateSource_setPreferredFrameRateRange(self, _cmd, appliedRange);
}

static void repl_CADynamicFrameRateSource_setHighFrameRateReasons_count(id self, SEL _cmd, const unsigned int *reasons, NSUInteger count) {
    if (!orig_CADynamicFrameRateSource_setHighFrameRateReasons_count) return;

    // Preserve Apple's clear/release path for non-persistent sources.
    // Protect single-owner sources (SB Global + App persistent) from system cleanup.
    if (!reasons || count == 0) {
        if (PMIsManagedSource(self)) {
            unsigned int persistReasons[1] = { 1U };
            orig_CADynamicFrameRateSource_setHighFrameRateReasons_count(self, _cmd, persistReasons, (NSUInteger)1);
            return;
        }
        orig_CADynamicFrameRateSource_setHighFrameRateReasons_count(self, _cmd, reasons, count);
        return;
    }

    if (PMIsEligibleNow() || PMFloatIsEligibleNow() || PMIsAppProcessEligible()) {
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
                // Register Darwin notification state so SpringBoard knows
                // this app has our hooks injected (skip keepalive)
                @try {
                    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
                    if (bundleID) {
                        char name[256];
                        snprintf(name, sizeof(name), "com.doimty.pm120.hooked.%s", [bundleID UTF8String]);
                        int regToken;
                        notify_register_check(name, &regToken);
                        notify_set_state(regToken, 1);
                        // Do NOT cancel — token must stay alive for state to persist
                    }
                } @catch (__unused NSException *e) {}
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
