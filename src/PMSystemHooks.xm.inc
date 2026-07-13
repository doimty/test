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
