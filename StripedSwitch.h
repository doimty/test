//
//  StripedSwitch.h
//  StripedSwitch (基于图片定制的清新斜条纹效果)
//

#import <UIKit/UIKit.h>

@interface StripedSwitch : UIView

/// 状态改变时的回调闭包
@property (nonatomic, copy, nullable) void (^changeAction)(BOOL, BOOL);

/// 开关的当前状态
@property (nonatomic, assign, getter=isOn) BOOL on;

- (nonnull instancetype)initWithFrame:(CGRect)frame;
- (CGFloat)knobMargin;

- (void)blockChangeActionAnimated:(BOOL)animated;
- (void)unblockChangeAction;
- (void)setOn:(BOOL)on animated:(BOOL)animated;

@end
