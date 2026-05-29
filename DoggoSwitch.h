//
//  DoggoSwitch.h
//  DoggoSwitch (1:1 完美复刻：解决漂移 + 修正短耳)
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface DoggoSwitch : UIView

/// 开关的当前状态 (YES = 开启/吐舌头, NO = 关闭/隐藏舌头)
@property (nonatomic, assign, getter=isOn) BOOL on;

/// 状态切换回调 (适配 Tweak 的双参数协议)
@property (nonatomic, copy, nullable) void (^changeAction)(BOOL, BOOL);

/// 带有动画控制的状态设置
- (void)setOn:(BOOL)on animated:(BOOL)animated;

// ================= Tweak 框架协议方法 =================
- (CGFloat)knobMargin;
- (void)blockChangeActionAnimated:(BOOL)animated;
- (void)unblockChangeAction;

@end

NS_ASSUME_NONNULL_END