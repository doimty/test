#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <objc/message.h>

#ifndef PM120_INLINE
#define PM120_INLINE static inline
#endif

// Recovered from com.promotion120 1.0.0-17+debug.
// Notes:
// - This is source reconstruction, not the lost original source.
// - Behavior intentionally mirrors the uploaded debug deb first.
// - Do not publish until tested on-device.

static BOOL pm120_checked = NO;
static BOOL pm120_supported = NO;

PM120_INLINE id PM120ClassCall0(Class cls, SEL sel) {
    if (!cls || !sel || ![cls respondsToSelector:sel]) return nil;
    return ((id (*)(Class, SEL))objc_msgSend)(cls, sel);
}

static BOOL deviceSupports120Hz(void) {
    if (pm120_checked) {
        return pm120_supported;
    }

    pm120_checked = YES;
    pm120_supported = NO;

    @try {
        Class CADisplayClass = NSClassFromString(@"CADisplay");
        SEL mainDisplaySel = NSSelectorFromString(@"mainDisplay");
        id display = PM120ClassCall0(CADisplayClass, mainDisplaySel);
        id modes = nil;

        if (display && [display respondsToSelector:@selector(valueForKey:)]) {
            modes = [display valueForKey:@"availableModes"];
        }

        for (id mode in modes) {
            id rateObject = nil;
            if ([mode respondsToSelector:@selector(valueForKey:)]) {
                rateObject = [mode valueForKey:@"refreshRate"];
            }
            double rate = [rateObject respondsToSelector:@selector(doubleValue)] ? [rateObject doubleValue] : 0.0;
            if (rate >= 119.0) {
                pm120_supported = YES;
                break;
            }
        }
    } @catch (__unused NSException *exception) {
        pm120_supported = NO;
    }

    return pm120_supported;
}

PM120_INLINE CAFrameRateRange PM120RangeFromOriginal(CAFrameRateRange original) {
    float minimum = original.minimum;
    if (minimum <= 0.0f || minimum > 120.0f) {
        minimum = 10.0f;
    }
    return CAFrameRateRangeMake(minimum, 120.0f, 120.0f);
}

PM120_INLINE CAFrameRateRange PM120DefaultRange(void) {
    return CAFrameRateRangeMake(10.0f, 120.0f, 120.0f);
}

PM120_INLINE NSTimeInterval PM120FrameDuration(void) {
    return 1.0 / 120.0;
}

%hook SBProMotionPolicy

- (NSInteger)maximumSupportedRefreshRate {
    return 120;
}

- (NSInteger)effectiveMaxRefreshRate {
    return 120;
}

- (BOOL)isLimitFrameRateEnabled {
    return NO;
}

- (BOOL)shouldLimitFrameRate {
    return NO;
}

%end

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

- (NSInteger)maximumRefreshRate {
    return 120;
}

%end

%hook UIScreen

- (NSInteger)maximumFramesPerSecond {
    if (deviceSupports120Hz()) {
        return 120;
    }
    return %orig;
}

%end

%hook CADisplayLink

+ (CADisplayLink *)displayLinkWithTarget:(id)target selector:(SEL)selector {
    CADisplayLink *link = %orig(target, selector);

    if (deviceSupports120Hz() && link) {
        if ([link respondsToSelector:@selector(setPreferredFrameRateRange:)]) {
            link.preferredFrameRateRange = PM120DefaultRange();
        } else if ([link respondsToSelector:@selector(setPreferredFramesPerSecond:)]) {
            link.preferredFramesPerSecond = 0;
        }
    }

    return link;
}

- (void)setPreferredFrameRateRange:(CAFrameRateRange)range {
    if (deviceSupports120Hz()) {
        %orig(PM120RangeFromOriginal(range));
        return;
    }
    %orig(range);
}

- (void)setPreferredFramesPerSecond:(NSInteger)fps {
    if (deviceSupports120Hz()) {
        %orig(0);
        return;
    }
    %orig(fps);
}

- (void)setFrameInterval:(NSInteger)interval {
    if (deviceSupports120Hz()) {
        %orig(1);
        return;
    }
    %orig(interval);
}

%end

%hook CAAnimation

- (void)setPreferredFrameRateRange:(CAFrameRateRange)range {
    if (deviceSupports120Hz()) {
        %orig(PM120RangeFromOriginal(range));
        return;
    }
    %orig(range);
}

%end

%hook CAMetalLayer

- (NSUInteger)maximumDrawableCount {
    NSUInteger original = %orig;
    if (deviceSupports120Hz() && original < 3) {
        return 3;
    }
    return original;
}

%end

%hook CAMetalDrawable

- (void)presentAfterMinimumDuration:(CFTimeInterval)duration {
    if (deviceSupports120Hz()) {
        %orig(PM120FrameDuration());
        return;
    }
    %orig(duration);
}

%end

%hook MTLCommandBuffer

- (void)presentDrawable:(id)drawable afterMinimumDuration:(CFTimeInterval)duration {
    if (deviceSupports120Hz()) {
        %orig(drawable, PM120FrameDuration());
        return;
    }
    %orig(drawable, duration);
}

%end
