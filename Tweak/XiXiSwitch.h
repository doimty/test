//
//  XiXiSwitch.h
//  XiXiSwitch (原生极致 3D 滚动大口版：不嘻嘻不挤，嘻嘻大口)
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface XiXiSwitch : UIView

/// 开关的当前状态 (YES = 开启/嘻嘻大口, NO = 关闭/不嘻嘻不挤)
@property (nonatomic, assign, getter=isOn) BOOL on;

/// 状态切换回调 (适配 Tweak)
@property (nonatomic, copy, nullable) void (^changeAction)(BOOL, BOOL);

/// 带有动画控制的状态设置
- (void)setOn:(BOOL)on animated:(BOOL)animated;

// ================= Tweak 框架协议方法 =================
- (CGFloat)knobMargin;
- (void)blockChangeActionAnimated:(BOOL)animated;
- (void)unblockChangeAction;
- (void)dns_disableAnimations;

@end

NS_ASSUME_NONNULL_END