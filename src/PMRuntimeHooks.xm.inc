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
// Original implementation pointer is defined by the Float module above.

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
    CAFrameRateRange appliedRange = range;
    // Always force 120Hz on our persistent sources
    if (PMIsManagedSource(self)) {
        appliedRange = PMForce120Range();
    } else if (PMBannerIsEligibleNow() || PMFloatIsEligibleNow()) {
        if (PMBannerIsEligibleNow()) PMSetHighFrameRateReasonIfPossible(self, NO, YES);
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

    if (PMBannerIsEligibleNow() || PMFloatIsEligibleNow() || PMIsAppProcessEligible()) {
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
