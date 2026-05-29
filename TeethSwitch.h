//
//  TeethSwitch.h
//  TeethSwitch (完美轨道倾斜版：高级灰 + 强制3D矩阵防屏蔽)
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface TeethSwitch : UIView

/// 开关的当前状态 (YES = 绿色/开启, NO = 灰色/关闭)
@property (nonatomic, assign, getter=isOn) BOOL on;

/// 状态切换回调 (适配 Tweak 的双参数协议)
@property (nonatomic, copy, nullable) void (^changeAction)(BOOL, BOOL);

/// 带有动画控制的状态设置
- (void)setOn:(BOOL)on animated:(BOOL)animated;

// ================= Tweak 框架协议方法 (防止闪退) =================
- (CGFloat)knobMargin;
- (void)blockChangeActionAnimated:(BOOL)animated;
- (void)unblockChangeAction;

@end

NS_ASSUME_NONNULL_END