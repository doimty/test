%hook CADisplayLink

// Hot path: no fake SB/Float/App branches. If device supports 120Hz, force it.
// Eligibility only gates DynamicSource lifecycle elsewhere, not per-link apply.

+ (CADisplayLink *)displayLinkWithTarget:(id)target selector:(SEL)sel {
    CADisplayLink *link = %orig;
    if (PMIsTargetProcess()) {
        PMJankRecordDisplayLinkTarget(PMClassName(target));
    }
    if (PMFloatFeatureEnabled()) {
        PMFloatDisplayLinkCreateCount += 1;
        PMFloatLastDisplayLinkTargetClass = [PMClassName(target) copy];
        if (link && PMFloatLastDisplayLinkTargetClass) {
            @try { objc_setAssociatedObject(link, PMFloatDisplayLinkTargetClassKey, PMFloatLastDisplayLinkTargetClass, OBJC_ASSOCIATION_COPY_NONATOMIC); } @catch (__unused NSException *e) {}
        }
        // In-process animation manager often drives float zoom. Arm on SB + plugin.
        if (PMFloatTargetIsInProcessAnimationManager(PMFloatLastDisplayLinkTargetClass) &&
            (PMFloatAnyFloatingWindowVisible() || PMFloatWindowConfirmed || PMFloatIsArmed())) {
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
    if (PMFloatFeatureEnabled()) {
        PMFloatDisplayLinkRangeSetCount += 1;
        PMFloatRecordRange(@"CADisplayLink.setPreferredFrameRateRange", range);
        if ((PMFloatAnyFloatingWindowVisible() || PMFloatWindowConfirmed || PMFloatIsArmed()) &&
            ((range.preferred > 0 && range.preferred < TARGET_FPS) || (range.maximum > 0 && range.maximum < TARGET_FPS))) {
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
