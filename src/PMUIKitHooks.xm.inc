%hook UIViewController

- (void)viewWillAppear:(BOOL)animated {
    if (!PMIsTargetProcess()) {
        // App processes: refresh persistent source on VC transitions
        PMAppRefreshPersistentSource();
    }
    // SpringBoard + floating-view package: arm Float when float windows are up.
    // Previously this arm sat inside !PMIsTargetProcess, so SB never armed here.
    if (PMFloatFeatureEnabled() && PMFloatAnyFloatingWindowVisible()) {
        PMFloatArm(@"vc.presentation");
    }
    %orig;
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    // Re-affirm 120Hz after VC transitions in app processes
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
    // Float windows often live in SpringBoard; arm on SB + floating-view package.
    if (PMFloatFeatureEnabled()) {
        @try {
            PMFloatProbeNoteGeometry(@"UIWindow.setFrame", PMClassName(self));
            if (PMFloatWindowLooksLikeStatusShrinkWindow((UIWindow *)self) && PMFloatRectLooksLikeCollapsedCapsule(frame) && PMFloatAnyFloatingWindowVisible()) {
                PMFloatPreArm(@"UIWindow.statusBar.smallFrame");
            }
            PMFloatArmForWindow((UIWindow *)self, @"UIWindow.setFrame");
        } @catch (__unused NSException *e) {}
    }
    %orig;
    if (PMFloatFeatureEnabled()) PMFloatReassertAfterGeometry(@"UIWindow.setFrame.post");
    return;
#endif
    if (PMFloatFeatureEnabled()) {
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
    if (PMFloatFeatureEnabled()) PMFloatReassertAfterGeometry(@"UIWindow.setFrame.post");
}

- (void)setBounds:(CGRect)bounds {
#if !PM_ENABLE_DIAGNOSTIC_PROBES
    if (PMFloatFeatureEnabled()) {
        @try {
            PMFloatProbeNoteGeometry(@"UIWindow.setBounds", PMClassName(self));
            PMFloatArmForWindow((UIWindow *)self, @"UIWindow.setBounds");
        } @catch (__unused NSException *e) {}
    }
    %orig;
    if (PMFloatFeatureEnabled()) PMFloatReassertAfterGeometry(@"UIWindow.setBounds.post");
    return;
#endif
    if (PMFloatFeatureEnabled()) {
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
        PMAppRefreshPersistentSource();
    }
    if (PMFloatFeatureEnabled()) {
        PMFloatArmForWindow((UIWindow *)self, @"window.makeKeyAndVisible");
    }
    %orig;
}

- (void)setWindowLevel:(UIWindowLevel)level {
    if (level >= 1000 && level < 2000 && PMFloatFeatureEnabled()) {
        NSString *winClass = PMClassName(self);
        PMFloatWriteState([NSString stringWithFormat:@"windowLevel=%.0f", (float)level], winClass ?: @"", YES);
        if (!PMIsTargetProcess()) PMAppRefreshPersistentSource();
        PMFloatArm(@"windowLevel.menu");
    }
    %orig;
}

%end

%hook UIView

- (void)setFrame:(CGRect)frame {
#if !PM_ENABLE_DIAGNOSTIC_PROBES
    if (PMFloatFeatureEnabled()) {
        @try {
            PMFloatProbeNoteGeometry(@"UIView.setFrame", PMClassName(self));
            if (PMFloatWindowLooksLikeStatusShrinkWindow(((UIView *)self).window) && PMFloatRectLooksLikeCollapsedCapsule(frame) && PMFloatAnyFloatingWindowVisible()) {
                PMFloatPreArm(@"UIView.statusBar.smallFrame");
            }
            PMFloatArmForView((UIView *)self, @"UIView.setFrame");
        } @catch (__unused NSException *e) {}
    }
    %orig;
    if (PMFloatFeatureEnabled()) PMFloatReassertAfterGeometry(@"UIView.setFrame.post");
    return;
#endif
    if (PMIsTargetProcess()) PMJankRecordViewMutation((UIView *)self, @"UIView.setFrame", frame, NO);
    if (PMFloatFeatureEnabled()) {
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
    if (PMFloatFeatureEnabled()) {
        @try {
            PMFloatProbeNoteGeometry(@"UIView.setBounds", PMClassName(self));
            PMFloatArmForView((UIView *)self, @"UIView.setBounds");
        } @catch (__unused NSException *e) {}
    }
    %orig;
    if (PMFloatFeatureEnabled()) PMFloatReassertAfterGeometry(@"UIView.setBounds.post");
    return;
#endif
    if (PMIsTargetProcess()) PMJankRecordViewMutation((UIView *)self, @"UIView.setBounds", bounds, YES);
    if (PMFloatFeatureEnabled()) {
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
    if (PMFloatFeatureEnabled() && (PMFloatAnyFloatingWindowVisible() || PMFloatWindowConfirmed || PMFloatIsArmed())) {
        PMFloatProbeNoteGeometry(@"UIViewPropertyAnimator.startAnimation", @"PropertyAnimator");
        PMFloatArmGeometry(@"UIViewPropertyAnimator.startAnimation");
    }
    %orig;
    if (PMFloatFeatureEnabled()) PMFloatReassertAfterGeometry(@"UIViewPropertyAnimator.startAnimation.post");
    return;
#endif
    if (PMIsTargetProcess()) PMJankRecordPropertyAnimator(@"UIViewPropertyAnimator.startAnimation");
    if (!PMIsTargetProcess()) PMAppRefreshPersistentSource();
    if (PMFloatFeatureEnabled() && (PMFloatAnyFloatingWindowVisible() || PMFloatWindowConfirmed || PMFloatIsArmed())) {
        PMFloatArmGeometry(@"UIViewPropertyAnimator.startAnimation");
    }
    %orig;
    if (PMFloatFeatureEnabled()) PMFloatReassertAfterGeometry(@"UIViewPropertyAnimator.startAnimation.post");
}

- (void)startAnimationAfterDelay:(NSTimeInterval)delay {
#if !PM_ENABLE_DIAGNOSTIC_PROBES
    if (PMFloatFeatureEnabled() && (PMFloatAnyFloatingWindowVisible() || PMFloatWindowConfirmed || PMFloatIsArmed())) {
        PMFloatArmGeometry(@"UIViewPropertyAnimator.startAnimationAfterDelay");
    }
    %orig;
    if (PMFloatFeatureEnabled()) PMFloatReassertAfterGeometry(@"UIViewPropertyAnimator.startAnimationAfterDelay.post");
    return;
#endif
    if (PMIsTargetProcess()) PMJankRecordPropertyAnimator(@"UIViewPropertyAnimator.startAnimationAfterDelay");
    if (PMFloatFeatureEnabled() && (PMFloatAnyFloatingWindowVisible() || PMFloatWindowConfirmed || PMFloatIsArmed())) {
        PMFloatArmGeometry(@"UIViewPropertyAnimator.startAnimationAfterDelay");
    }
    %orig;
    if (PMFloatFeatureEnabled()) PMFloatReassertAfterGeometry(@"UIViewPropertyAnimator.startAnimationAfterDelay.post");
}

%end

%hook CALayer

- (void)addAnimation:(CAAnimation *)animation forKey:(NSString *)key {
    if (PMBannerIsEligibleNow() && animation && PMLayerBelongsToBannerWindow((CALayer *)self)) {
        PMApplyToCAObject(animation, NO, NO);
    }
#if !PM_ENABLE_DIAGNOSTIC_PROBES
    if (PMFloatFeatureEnabled()) {
        @try {
            NSString *floatKey = [key copy] ?: @"";
            PMFloatLastAnimationKey = floatKey;
            PMFloatProbeNoteGeometry(@"CALayer.addAnimation", PMClassName(self));
            BOOL geometryKey = ([floatKey isEqualToString:@"opacity"] || [floatKey containsString:@"position"] || [floatKey containsString:@"bounds"] || [floatKey containsString:@"transform"] || [floatKey containsString:@"frame"] || [floatKey containsString:@"size"] || [floatKey containsString:@"scale"]);
            if (geometryKey && (PMFloatAnyFloatingWindowVisible() || PMFloatWindowConfirmed || PMFloatIsArmed())) {
                PMFloatPreArm([NSString stringWithFormat:@"CALayer.addAnimation.%@", floatKey ?: @""]);
            }
            PMFloatArmForLayer((CALayer *)self, @"CALayer.addAnimation");
            if (animation && (PMFloatIsEligibleNow() || PMFloatWindowConfirmed || PMFloatIsArmed() || PMFloatAnyFloatingWindowVisible())) {
                PMApplyToCAObjectDirect(animation);
            }
        } @catch (__unused NSException *e) {}
    }
    %orig;
    if (PMFloatFeatureEnabled()) PMFloatReassertAfterGeometry(@"CALayer.addAnimation.post");
    return;
#endif
    if (PMIsTargetProcess()) PMJankRecordLayerAnimation((CALayer *)self, animation, key);
    if (PMFloatFeatureEnabled()) {
        PMFloatLayerAddAnimationCount += 1;
        PMFloatLastLayerClass = [PMClassName(self) copy];
        PMFloatLastAnimationClass = [PMClassName(animation) copy];
        PMFloatLastAnimationKey = [key copy] ?: @"";
        PMFloatWriteState(@"CALayer.addAnimation", PMFloatLastAnimationKey ?: @"", NO);
        BOOL geometryKey = ([PMFloatLastAnimationKey isEqualToString:@"opacity"] || [PMFloatLastAnimationKey containsString:@"position"] || [PMFloatLastAnimationKey containsString:@"bounds"] || [PMFloatLastAnimationKey containsString:@"transform"] || [PMFloatLastAnimationKey containsString:@"frame"] || [PMFloatLastAnimationKey containsString:@"size"] || [PMFloatLastAnimationKey containsString:@"scale"]);
        if (geometryKey && (PMFloatAnyFloatingWindowVisible() || PMFloatWindowConfirmed || PMFloatIsArmed())) {
            PMFloatPreArm([NSString stringWithFormat:@"CALayer.addAnimation.%@", PMFloatLastAnimationKey ?: @""]);
        }
        PMFloatArmForLayer((CALayer *)self, @"CALayer.addAnimation");
        if (animation && (PMFloatIsEligibleNow() || PMFloatWindowConfirmed || PMFloatIsArmed() || PMFloatAnyFloatingWindowVisible())) {
            PMApplyToCAObjectDirect(animation);
        }
    }
    %orig;
    if (PMFloatFeatureEnabled()) PMFloatReassertAfterGeometry(@"CALayer.addAnimation.post");
}

- (void)setBounds:(CGRect)bounds {
#if !PM_ENABLE_DIAGNOSTIC_PROBES
    if (PMFloatFeatureEnabled()) {
        @try {
            PMFloatProbeNoteGeometry(@"CALayer.setBounds", PMClassName(self));
            PMFloatArmForLayer((CALayer *)self, @"CALayer.setBounds");
        } @catch (__unused NSException *e) {}
    }
    %orig;
    if (PMFloatFeatureEnabled()) PMFloatReassertAfterGeometry(@"CALayer.setBounds.post");
    return;
#endif
    if (PMIsTargetProcess()) PMJankRecordLayerMutation((CALayer *)self, @"CALayer.setBounds");
    if (PMFloatFeatureEnabled()) {
        PMFloatLayerSetBoundsCount += 1;
        PMFloatLastLayerClass = [PMClassName(self) copy];
        PMFloatLastBounds = bounds;
        PMFloatWriteState(@"CALayer.setBounds", PMFloatLastLayerClass ?: @"", NO);
        PMFloatArmForLayer((CALayer *)self, @"CALayer.setBounds");
    }
    %orig;
    if (PMFloatFeatureEnabled()) PMFloatReassertAfterGeometry(@"CALayer.setBounds.post");
}

- (void)setPosition:(CGPoint)position {
#if !PM_ENABLE_DIAGNOSTIC_PROBES
    if (PMFloatFeatureEnabled()) {
        @try {
            PMFloatProbeNoteGeometry(@"CALayer.setPosition", PMClassName(self));
            PMFloatArmForLayer((CALayer *)self, @"CALayer.setPosition");
        } @catch (__unused NSException *e) {}
    }
    %orig;
    if (PMFloatFeatureEnabled()) PMFloatReassertAfterGeometry(@"CALayer.setPosition.post");
    return;
#endif
    if (PMIsTargetProcess()) PMJankRecordLayerMutation((CALayer *)self, @"CALayer.setPosition");
    if (PMFloatFeatureEnabled()) {
        PMFloatLayerSetPositionCount += 1;
        PMFloatLastLayerClass = [PMClassName(self) copy];
        PMFloatLastPosition = position;
        PMFloatWriteState(@"CALayer.setPosition", PMFloatLastLayerClass ?: @"", NO);
        PMFloatArmForLayer((CALayer *)self, @"CALayer.setPosition");
    }
    %orig;
    if (PMFloatFeatureEnabled()) PMFloatReassertAfterGeometry(@"CALayer.setPosition.post");
}

- (void)setTransform:(CATransform3D)transform {
#if !PM_ENABLE_DIAGNOSTIC_PROBES
    if (PMFloatFeatureEnabled()) {
        @try {
            PMFloatProbeNoteGeometry(@"CALayer.setTransform", PMClassName(self));
            PMFloatArmForLayer((CALayer *)self, @"CALayer.setTransform");
        } @catch (__unused NSException *e) {}
    }
    %orig;
    if (PMFloatFeatureEnabled()) PMFloatReassertAfterGeometry(@"CALayer.setTransform.post");
    return;
#endif
    if (PMIsTargetProcess()) PMJankRecordLayerMutation((CALayer *)self, @"CALayer.setTransform");
    if (PMFloatFeatureEnabled()) {
        PMFloatLayerSetTransformCount += 1;
        PMFloatLastLayerClass = [PMClassName(self) copy];
        PMFloatWriteState(@"CALayer.setTransform", PMFloatLastLayerClass ?: @"", NO);
        PMFloatArmForLayer((CALayer *)self, @"CALayer.setTransform");
    }
    %orig;
    if (PMFloatFeatureEnabled()) PMFloatReassertAfterGeometry(@"CALayer.setTransform.post");
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
