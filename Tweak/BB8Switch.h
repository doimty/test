//
//  BB8Switch.h
//  BB8Switch (星战 BB-8 日夜交替场景开关)
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface BB8Switch : UIView

/// 开关的当前状态 (YES = 夜晚/太空, NO = 白天/塔图因)
@property (nonatomic, assign, getter=isOn) BOOL on;

/// 状态切换回调 (适配 Tweak 的双参数协议)
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