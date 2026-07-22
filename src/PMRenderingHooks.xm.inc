%hook CADisplayLink

// Hot path: no fake SB/Float/App branches. If device supports 120Hz, force it.
// Eligibility only gates DynamicSource lifecycle elsewhere, not per-link apply.

+ (CADisplayLink *)displayLinkWithTarget:(id)target selector:(SEL)sel {
    CADisplayLink *link = %orig;
    if (!PMIsTargetProcess()) {
        NSString *targetClass = PMClassName(target);
        if (link && targetClass.length > 0) {
            @try { objc_setAssociatedObject(link, PMFloatDisplayLinkTargetClassKey, targetClass, OBJC_ASSOCIATION_COPY_NONATOMIC); } @catch (__unused NSException *e) {}
        }
        if (PMFloatTargetIsInProcessAnimationManager(targetClass) && PMFloatAnyFloatingWindowVisible()) {
            PMFloatPreArm(@"CADisplayLink.UIViewInProcessAnimationManager");
        }
    }
    if (PMDeviceSupports120Hz() && link) {
        PMApplyToCAObjectDirect(link);
    }
    return link;
}

- (void)setPreferredFrameRateRange:(CAFrameRateRange)range {
    if (!PMIsTargetProcess()) {
        if (PMFloatAnyFloatingWindowVisible() && ((range.preferred > 0 && range.preferred < TARGET_FPS) || (range.maximum > 0 && range.maximum < TARGET_FPS))) {
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
        NSString *targetClass = PMFloatDisplayLinkTargetClass(self);
        if (PMFloatAnyFloatingWindowVisible() && fps > 0 && fps < TARGET_FPS) {
            NSString *reason = PMFloatTargetIsInProcessAnimationManager(targetClass) ? @"CADisplayLink.lowFPS.UIViewInProcessAnimationManager" : @"CADisplayLink.lowFPS";
            PMFloatPreArm(reason);
        }
    }
    if (PMDeviceSupports120Hz()) {
        PMSetHighFrameRateReasonDirect(self);
        %orig(TARGET_FPS);
    } else {
        %orig;
    }
}

- (void)setFrameInterval:(NSInteger)interval {
    if (PMDeviceSupports120Hz()) {
        PMSetHighFrameRateReasonDirect(self);
        %orig(1);
    } else {
        %orig;
    }
}

%end

%hook CAAnimation

- (void)setPreferredFrameRateRange:(CAFrameRateRange)range {
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
