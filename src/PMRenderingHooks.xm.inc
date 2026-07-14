%hook CADisplayLink

// Hot path: no fake SB/Float/App branches. If device supports 120Hz, force it.
// Eligibility only gates DynamicSource lifecycle elsewhere, not per-link apply.

+ (CADisplayLink *)displayLinkWithTarget:(id)target selector:(SEL)sel {
    CADisplayLink *link = %orig;
#if PM_ENABLE_DIAGNOSTIC_PROBES
    if (PMIsTargetProcess()) {
        PMJankRecordDisplayLinkTarget(PMClassName(target));
    }
#endif
    if (!PMIsTargetProcess()) {
        NSString *targetClass = PMClassName(target);
#if PM_ENABLE_DIAGNOSTIC_PROBES
        PMFloatDisplayLinkCreateCount += 1;
        PMFloatLastDisplayLinkTargetClass = [targetClass copy];
        if (link && PMFloatLastDisplayLinkTargetClass) {
            @try { objc_setAssociatedObject(link, PMFloatDisplayLinkTargetClassKey, PMFloatLastDisplayLinkTargetClass, OBJC_ASSOCIATION_COPY_NONATOMIC); } @catch (__unused NSException *e) {}
        }
#endif
        if (PMFloatTargetIsInProcessAnimationManager(targetClass) && PMFloatAnyFloatingWindowVisible()) {
#if PM_ENABLE_DIAGNOSTIC_PROBES
            PMFloatPreArmInProcessManagerCount += 1;
#endif
            PMFloatPreArm(@"CADisplayLink.UIViewInProcessAnimationManager");
        }
#if PM_ENABLE_DIAGNOSTIC_PROBES
        PMFloatWriteState(@"CADisplayLink.displayLinkWithTarget", targetClass ?: @"", YES);
#endif
    }
    if (PMDeviceSupports120Hz() && link) {
        PMApplyToCAObjectDirect(link);
    }
    return link;
}

- (void)setPreferredFrameRateRange:(CAFrameRateRange)range {
    if (!PMIsTargetProcess()) {
#if PM_ENABLE_DIAGNOSTIC_PROBES
        PMFloatDisplayLinkRangeSetCount += 1;
        PMFloatRecordRange(@"CADisplayLink.setPreferredFrameRateRange", range);
#endif
        if (PMFloatAnyFloatingWindowVisible() && ((range.preferred > 0 && range.preferred < TARGET_FPS) || (range.maximum > 0 && range.maximum < TARGET_FPS))) {
#if PM_ENABLE_DIAGNOSTIC_PROBES
            PMFloatPreArmLowFPSCount += 1;
#endif
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
#if PM_ENABLE_DIAGNOSTIC_PROBES
        PMFloatDisplayLinkFPSSetCount += 1;
        PMFloatLastPreferredFPS = fps;
        NSString *targetClass = PMFloatDisplayLinkTargetClass(self);
        if (targetClass.length > 0) PMFloatLastDisplayLinkTargetClass = [targetClass copy];
#else
        NSString *targetClass = PMFloatDisplayLinkTargetClass(self);
#endif
        if (PMFloatAnyFloatingWindowVisible() && fps > 0 && fps < TARGET_FPS) {
#if PM_ENABLE_DIAGNOSTIC_PROBES
            PMFloatPreArmLowFPSCount += 1;
#endif
            NSString *reason = PMFloatTargetIsInProcessAnimationManager(targetClass) ? @"CADisplayLink.lowFPS.UIViewInProcessAnimationManager" : @"CADisplayLink.lowFPS";
            PMFloatPreArm(reason);
        }
#if PM_ENABLE_DIAGNOSTIC_PROBES
        PMFloatWriteState(@"CADisplayLink.setPreferredFramesPerSecond", [NSString stringWithFormat:@"fps=%ld target=%@", (long)fps, targetClass ?: @""], NO);
#endif
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
#if PM_ENABLE_DIAGNOSTIC_PROBES
        PMFloatDisplayLinkFrameIntervalSetCount += 1;
        PMFloatLastFrameInterval = interval;
        PMFloatWriteState(@"CADisplayLink.setFrameInterval", [NSString stringWithFormat:@"interval=%ld", (long)interval], NO);
#endif
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
#if PM_ENABLE_DIAGNOSTIC_PROBES
        PMFloatAnimationRangeSetCount += 1;
        PMFloatLastAnimationClass = [PMClassName(self) copy];
        PMFloatRecordRange(@"CAAnimation.setPreferredFrameRateRange", range);
#endif
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
