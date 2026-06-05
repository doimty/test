#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
#import <rootless.h>
#import <Metal/Metal.h>

// ============================================================
#define TWEAK_NAME @"ProMotion120"
#define TARGET_FPS 120

// ============================================================
// CAFrameRateRange 结构体定义 (iOS 15+)
// ============================================================
#ifndef __IPHONE_15_0
typedef struct {
    float minimum;
    float preferred;
    float maximum;
} CAFrameRateRange;
#endif

// ============================================================
// 真实硬件 ProMotion 检测 (通过 QuartzCore CADisplay)
// 绕过 iOS 16 对未授权应用进程的 UIScreen.maximumFramesPerSecond 限制 (返回 60)
// ============================================================
@interface CADisplayMode : NSObject
@property (nonatomic, readonly) double refreshRate;
@end

@interface CADisplay : NSObject
+ (CADisplay *)mainDisplay;
@property (nonatomic, readonly) NSArray *availableModes;
@end

static BOOL deviceSupports120Hz(void) {
    static BOOL checked = NO;
    static BOOL supported = NO;
    if (!checked) {
        @autoreleasepool {
            Class CADisplayClass = NSClassFromString(@"CADisplay");
            if (CADisplayClass) {
                CADisplay *mainDisplay = [CADisplayClass performSelector:@selector(mainDisplay)];
                if (mainDisplay) {
                    NSArray *modes = [mainDisplay valueForKey:@"availableModes"];
                    for (id mode in modes) {
                        double rate = [[mode valueForKey:@"refreshRate"] doubleValue];
                        if (rate >= 119.0) {
                            supported = YES;
                            break;
                        }
                    }
                }
            }
        }
        checked = YES;
    }
    return supported;
}

// ============================================================
// 层次 1: SBProMotionPolicy Hook
// 从系统策略层面解除 80Hz 限制 (仅在 SpringBoard 进程生效)
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

// ============================================================
// 低电量模式绕过
// 确保低电量模式下也保持 120Hz
// ============================================================

@interface SBLowPowerModeController : NSObject
+ (instancetype)sharedInstance;
- (BOOL)isInLowPowerMode;
@end

@interface _CDBatterySaver : NSObject
+ (id)batterySaver;
- (NSInteger)getPowerMode;
@end

// Hook SpringBoard 的低电量模式控制器
%hook SBLowPowerModeController

- (BOOL)isInLowPowerMode {
    return NO;
}

%end

// Hook 核心电量保存服务 (CoreDuet)
%hook _CDBatterySaver

- (NSInteger)getPowerMode {
    return 0; // 0 = 正常模式, 1 = 低电量模式
}

%end

// Hook NSProcessInfo 的低电量模式检测 (App 和 SpringBoard)
%hook NSProcessInfo

- (BOOL)isLowPowerModeEnabled {
    return NO;
}

%end

// ============================================================
// 层次 2: SBDisplayRefreshRateController Hook
// 确保刷新率控制器支持最大 120Hz
// ============================================================
%hook SBDisplayRefreshRateController

- (long long)maximumRefreshRate {
    return TARGET_FPS;
}

%end

// ============================================================
// UIScreen 欺骗 Hook
// 确保第三方应用查询主屏幕最大帧率时也能得到 120Hz 从而激活自身的 120Hz 布局 and 帧率自适应
// ============================================================
%hook UIScreen

- (NSInteger)maximumFramesPerSecond {
    if (deviceSupports120Hz()) {
        return TARGET_FPS;
    }
    return %orig;
}

%end

// ============================================================
// 层次 3: CADisplayLink Hook
// 强制所有 CADisplayLink 实例请求最大帧率
// ============================================================
%hook CADisplayLink

// Factory method Hook
// 拦截 CADisplayLink 创建时，赋予安全的帧率范围，防止默认采用 60Hz 限制范围
+ (CADisplayLink *)displayLinkWithTarget:(id)target selector:(SEL)sel {
    CADisplayLink *link = %orig;
    if (deviceSupports120Hz()) {
        if ([link respondsToSelector:@selector(setPreferredFrameRateRange:)]) {
            CAFrameRateRange range;
            range.minimum = 10;                 // 允许降至最低 10Hz 省电
            range.preferred = TARGET_FPS;       // 120Hz
            range.maximum = TARGET_FPS;         // 120Hz
            [link setPreferredFrameRateRange:range];
        } else if ([link respondsToSelector:@selector(setPreferredFramesPerSecond:)]) {
            [link setPreferredFramesPerSecond:0];
        }
    }
    return link;
}

// Hook preferredFrameRateRange (iOS 15+)
- (void)setPreferredFrameRateRange:(CAFrameRateRange)range {
    if (deviceSupports120Hz()) {
        CAFrameRateRange newRange;
        // 保证 minimum <= preferred <= maximum 约束，防止抛出异常
        newRange.minimum = (range.minimum > 0 && range.minimum <= TARGET_FPS) ? range.minimum : 10;
        newRange.preferred = TARGET_FPS;
        newRange.maximum = TARGET_FPS;
        
        // 双重保险：如果原设置 the minimum 大于 120，则修正它
        if (newRange.minimum > TARGET_FPS) {
            newRange.minimum = 10;
        }
        %orig(newRange);
    } else {
        %orig;
    }
}

// Hook preferredFramesPerSecond (iOS 10-15)
- (void)setPreferredFramesPerSecond:(NSInteger)fps {
    if (deviceSupports120Hz()) {
        %orig(0); // 0 = 使用设备最大帧率
    } else {
        %orig;
    }
}

// Hook frameInterval
- (void)setFrameInterval:(NSInteger)interval {
    if (deviceSupports120Hz()) {
        %orig(1); // 1 = 每帧渲染，不做稀释
    } else {
        %orig;
    }
}

%end

// ============================================================
// CAAnimation Hook
// 拦截 CoreAnimation 动画更新周期，将其帧率范围上限拓展为 120Hz
// ============================================================
%hook CAAnimation

- (void)setPreferredFrameRateRange:(CAFrameRateRange)range {
    if (deviceSupports120Hz()) {
        CAFrameRateRange newRange;
        newRange.minimum = (range.minimum > 0 && range.minimum <= TARGET_FPS) ? range.minimum : 10;
        newRange.preferred = TARGET_FPS;
        newRange.maximum = TARGET_FPS;
        
        if (newRange.minimum > TARGET_FPS) {
            newRange.minimum = 10;
        }
        %orig(newRange);
    } else {
        %orig;
    }
}

%end

// ============================================================
// CAMetalLayer Hook (Metal 渲染优化)
// 确保 Metal 应用使用三重缓冲且解除最长呈现延迟
// ============================================================
@interface CAMetalLayer (Private)
@property (assign) NSUInteger maximumDrawableCount;
@end

%hook CAMetalLayer

- (NSUInteger)maximumDrawableCount {
    NSUInteger orig = %orig;
    if (deviceSupports120Hz() && orig < 3) {
        return 3; // 三重缓冲以支持 120Hz
    }
    return orig;
}

%end

%hook CAMetalDrawable

- (void)presentAfterMinimumDuration:(CFTimeInterval)duration {
    if (deviceSupports120Hz()) {
        %orig(1.0 / TARGET_FPS);
    } else {
        %orig;
    }
}

%end

%hook MTLCommandBuffer

- (void)presentDrawable:(id)drawable afterMinimumDuration:(CFTimeInterval)minimumDuration {
    if (deviceSupports120Hz()) {
        %orig(drawable, 1.0 / TARGET_FPS);
    } else {
        %orig(drawable, minimumDuration);
    }
}

%end

// ============================================================
// 构造函数 - 插件加载入口
// ============================================================
%ctor {
    @autoreleasepool {
        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
        NSLog(@"[%@] 载入进程: %@", TWEAK_NAME, bundleID ?: @"unknown");
        
        if (deviceSupports120Hz()) {
            %init;
            NSLog(@"[%@] ✅ Hook 初始化完成 (动态 120Hz 全局模式)", TWEAK_NAME);
        } else {
            NSLog(@"[%@] ⚠️ 设备不支持 120Hz ProMotion，跳过注入", TWEAK_NAME);
        }
    }
}
