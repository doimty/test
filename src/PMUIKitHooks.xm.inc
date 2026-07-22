%hook UIViewController

- (void)viewWillAppear:(BOOL)animated {
    if (!PMIsTargetProcess()) {
        PMAppRefreshPersistentSource();
    }
    if (PMFloatFeatureEnabled() && PMFloatAnyFloatingWindowVisible()) {
        PMFloatArm(@"vc.presentation");
    }
    %orig;
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    if (!PMIsTargetProcess()) PMAppRefreshPersistentSource();
    if (PMFloatFeatureEnabled() && PMFloatAnyFloatingWindowVisible()) {
        PMFloatArm(@"vc.didAppear");
    }
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

// List view hooks removed with jank probes (no functional side effects).

%hook UIWindow

- (void)setFrame:(CGRect)frame {
    if (PMFloatFeatureEnabled()) {
        @try {
            if (PMFloatWindowLooksLikeStatusShrinkWindow((UIWindow *)self) && PMFloatRectLooksLikeCollapsedCapsule(frame) && PMFloatAnyFloatingWindowVisible()) {
                PMFloatPreArm(@"UIWindow.statusBar.smallFrame");
            }
            PMFloatArmForWindow((UIWindow *)self, @"UIWindow.setFrame");
        } @catch (__unused NSException *e) {}
    }
    %orig;
}

- (void)setBounds:(CGRect)bounds {
    if (PMFloatFeatureEnabled()) {
        @try { PMFloatArmForWindow((UIWindow *)self, @"UIWindow.setBounds"); } @catch (__unused NSException *e) {}
    }
    %orig;
}

- (void)makeKeyAndVisible {
    if (!PMIsTargetProcess()) {
        PMAppRefreshPersistentSource();
    }
    if (PMFloatFeatureEnabled()) {
        PMFloatArmForWindow((UIWindow *)self, @"window.makeKeyAndVisible");
    }
    %orig;
}

- (void)setWindowLevel:(UIWindowLevel)level {
    if (level >= 1000 && level < 2000 && PMFloatFeatureEnabled()) {
        if (!PMIsTargetProcess()) PMAppRefreshPersistentSource();
        PMFloatArm(@"windowLevel.menu");
    }
    %orig;
}

%end

%hook UIView

- (void)setFrame:(CGRect)frame {
    if (PMFloatFeatureEnabled()) {
        @try {
            if (PMFloatWindowLooksLikeStatusShrinkWindow(((UIView *)self).window) && PMFloatRectLooksLikeCollapsedCapsule(frame) && PMFloatAnyFloatingWindowVisible()) {
                PMFloatPreArm(@"UIView.statusBar.smallFrame");
            }
            PMFloatArmForView((UIView *)self, @"UIView.setFrame");
        } @catch (__unused NSException *e) {}
    }
    %orig;
}

- (void)setBounds:(CGRect)bounds {
    if (PMFloatFeatureEnabled()) {
        @try { PMFloatArmForView((UIView *)self, @"UIView.setBounds"); } @catch (__unused NSException *e) {}
    }
    %orig;
}

%end

%hook UIScrollView

- (void)setContentOffset:(CGPoint)contentOffset {
    if (PMIsTargetProcess()) {
        PMGlobalSBApply(@"UIScrollView.setContentOffset");
    } else {
#if PM_FOREGROUND_PROBE_ENABLED
        PMFGProbeRecordScroll(PMFGProbeScrollSourceSetContentOffset);
#endif
        @try { PMAppScrollArm(@"UIScrollView.setContentOffset"); } @catch (__unused NSException *e) {}
    }
    %orig;
}

- (void)setContentOffset:(CGPoint)contentOffset animated:(BOOL)animated {
    if (PMIsTargetProcess()) {
        PMGlobalSBApply(@"UIScrollView.setContentOffsetAnimated");
    } else {
#if PM_FOREGROUND_PROBE_ENABLED
        PMFGProbeRecordScroll(PMFGProbeScrollSourceSetContentOffsetAnimated);
#endif
        @try { PMAppScrollArm(@"UIScrollView.setContentOffsetAnimated"); } @catch (__unused NSException *e) {}
    }
    %orig;
}

- (void)layoutSubviews {
    if (!PMIsTargetProcess()) {
        @try {
            if (PMAppScrollViewIsMoving((UIScrollView *)self)) {
#if PM_FOREGROUND_PROBE_ENABLED
                PMFGProbeRecordScroll(PMFGProbeScrollSourceLayoutMoving);
#endif
                PMAppScrollArm(@"UIScrollView.layoutSubviews.moving");
            }
        } @catch (__unused NSException *e) {}
    }
    %orig;
}

%end

%hook UIViewPropertyAnimator

- (void)startAnimation {
    if (!PMIsTargetProcess()) PMAppRefreshPersistentSource();
    if (PMFloatFeatureEnabled() && PMFloatAnyFloatingWindowVisible()) {
        PMFloatArm(@"UIViewPropertyAnimator.startAnimation");
    }
    %orig;
}

- (void)startAnimationAfterDelay:(NSTimeInterval)delay {
    if (PMFloatFeatureEnabled() && PMFloatAnyFloatingWindowVisible()) {
        PMFloatArm(@"UIViewPropertyAnimator.startAnimationAfterDelay");
    }
    %orig;
}

%end

%hook CALayer

- (void)addAnimation:(CAAnimation *)animation forKey:(NSString *)key {
    if (PMBannerIsEligibleNow() && animation && PMLayerBelongsToBannerWindow((CALayer *)self)) {
        PMApplyToCAObject(animation, NO, NO);
    }
    if (PMFloatFeatureEnabled()) {
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
}

- (void)setBounds:(CGRect)bounds {
    if (PMFloatFeatureEnabled()) {
        @try { PMFloatArmForLayer((CALayer *)self, @"CALayer.setBounds"); } @catch (__unused NSException *e) {}
    }
    %orig;
}

- (void)setPosition:(CGPoint)position {
    if (PMFloatFeatureEnabled()) {
        @try { PMFloatArmForLayer((CALayer *)self, @"CALayer.setPosition"); } @catch (__unused NSException *e) {}
    }
    %orig;
}

- (void)setTransform:(CATransform3D)transform {
    if (PMFloatFeatureEnabled()) {
        @try { PMFloatArmForLayer((CALayer *)self, @"CALayer.setTransform"); } @catch (__unused NSException *e) {}
    }
    %orig;
}

%end

// Ordinary apps: only refresh App persistent source.
// Float arm is gated internally (floating package / floating window only).
%hook UIAlertController
- (void)viewDidAppear:(BOOL)animated {
    if (!PMIsTargetProcess()) {
        PMAppRefreshPersistentSource();
    }
    %orig;
}
%end

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

%hook UIPopoverPresentationController
- (void)viewDidAppear:(BOOL)animated {
    if (!PMIsTargetProcess()) PMAppRefreshPersistentSource();
    %orig;
}
%end
