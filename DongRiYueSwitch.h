//
//  DayNightSwitch.h
//  DayNightSwitch (防闪退补丁版：补全 Tweak 协议接口 + 安全内存桥接)
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface DongRiYueSwitch : UIView

/// 开关的当前状态
@property (nonatomic, assign, getter=isOn) BOOL on;

/// 严格对应原版 Tweak 的双参数回调闭包
@property (nonatomic, copy, nullable) void (^changeAction)(BOOL, BOOL);

/// 带有动画控制的状态设置
- (void)setOn:(BOOL)on animated:(BOOL)animated;

// ================= Tweak 框架协议方法 (防止闪退的核心) =================
- (CGFloat)knobMargin;
- (void)blockChangeActionAnimated:(BOOL)animated;
- (void)unblockChangeAction;
- (void)dns_disableAnimations;

@end

NS_ASSUME_NONNULL_END