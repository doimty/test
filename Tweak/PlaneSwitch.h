//
//  PlaneSwitch.h
//  PlaneSwitch (飞机航线开关 - 完美复刻版)
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface PlaneSwitch : UIView

/// 开关的当前状态 (YES = 天空/开启, NO = 跑道/关闭)
@property (nonatomic, assign, getter=isOn) BOOL on;

/// 状态切换回调 (适配 Tweak 的双参数协议)
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