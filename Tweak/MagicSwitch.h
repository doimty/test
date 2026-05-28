//
//  MagicSwitch.h
//  MagicSwitch (1:1 纯血复刻 CSS 效果)
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface MagicSwitch : UIView

/// 开关的当前状态 (YES = 夜晚/开启, NO = 白天/关闭)
@property (nonatomic, assign, getter=isOn) BOOL on;

/// 状态切换回调 (适配 Tweak 的双参数协议)
@property (nonatomic, copy, nullable) void (^changeAction)(BOOL, BOOL);

/// 带有动画控制的状态设置
- (void)setOn:(BOOL)on animated:(BOOL)animated;

// ================= Tweak 框架协议方法 (防止闪退) =================
- (CGFloat)knobMargin;
- (void)blockChangeActionAnimated:(BOOL)animated;
- (void)unblockChangeAction;
- (void)dns_disableAnimations;

@end

NS_ASSUME_NONNULL_END