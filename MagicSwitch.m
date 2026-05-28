//
//  MagicSwitch.m
//  MagicSwitch
//

#import "MagicSwitch.h"

// 颜色宏辅助
#define ColorHex(hexValue) [UIColor colorWithRed:((float)((hexValue & 0xFF0000) >> 16))/255.0 green:((float)((hexValue & 0xFF00) >> 8))/255.0 blue:((float)(hexValue & 0xFF))/255.0 alpha:1.0]
#define ColorHexA(hexValue, a) [UIColor colorWithRed:((float)((hexValue & 0xFF0000) >> 16))/255.0 green:((float)((hexValue & 0xFF00) >> 8))/255.0 blue:((float)(hexValue & 0xFF))/255.0 alpha:(a)]

@interface MagicSwitch ()

@property (nonatomic, strong) UIView *trackContainer;
@property (nonatomic, strong) UIView *trackView; // 带有 overflow: hidden

// 背景层
@property (nonatomic, strong) UIView *dayBgView;
@property (nonatomic, strong) CAGradientLayer *dayGradLayer;
@property (nonatomic, strong) UIView *dayHoverBgView;
@property (nonatomic, strong) CAGradientLayer *dayHoverGradLayer;

@property (nonatomic, strong) UIView *nightBgView;
@property (nonatomic, strong) CAGradientLayer *nightGradLayer;
@property (nonatomic, strong) UIView *nightHoverBgView;
@property (nonatomic, strong) CAGradientLayer *nightHoverGradLayer;

// 星星
@property (nonatomic, strong) UIView *star1;
@property (nonatomic, strong) UIView *star2;

// 滑块
@property (nonatomic, strong) UIView *knobContainer; // 用于平移和翻转
@property (nonatomic, strong) UIView *knobBaseView;  // 用于颜色和裁剪内阴影
@property (nonatomic, strong) UIView *moonInsetShadow; // 模拟 inset -10px -5px 0 0 #ddd
@property (nonatomic, strong) UIView *sunGlowView;   // 太阳脉冲
@property (nonatomic, strong) UIView *moonGlowView;  // 月亮光晕

// 伪元素 (云朵 <=> 陨石坑 变形复用)
@property (nonatomic, strong) UIView *pseudoElementBefore; // slider-inner::before
@property (nonatomic, strong) UIView *pseudoElementAfter;  // slider-inner::after

@property (nonatomic, assign) CGFloat em;

@property (nonatomic, assign, getter=isMoved) BOOL moved;
@property (nonatomic, assign, getter=isDragging) BOOL dragging;
@property (nonatomic, assign, getter=isOnBeforeDrag) BOOL onBeforeDrag;
@property (nonatomic, assign, getter=isHovering) BOOL hovering;

@end

@implementation MagicSwitch {
    BOOL _shouldSkipChangeAction;
    BOOL _shouldAnimateImportant;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) { [self commonInit]; }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super initWithCoder:coder];
    if (self) { [self commonInit]; }
    return self;
}

- (void)commonInit {
    self.backgroundColor = [UIColor clearColor];
    _on = NO;
    _hovering = NO;
    self.moved = NO;
    self.dragging = NO;
    _shouldAnimateImportant = YES;

    // CSS 比例：高度是 3em，宽度是 6em。我们以高度为基准计算 1em 的像素值。
    _em = self.bounds.size.height / 3.0;
    CGFloat trackWidth = 6.0 * _em;
    CGFloat trackHeight = 3.0 * _em;

    // 居中容器 (防止外界给的 frame 比例不对)
    self.trackContainer = [[UIView alloc] initWithFrame:CGRectMake((self.bounds.size.width - trackWidth)/2.0, (self.bounds.size.height - trackHeight)/2.0, trackWidth, trackHeight)];

    // 3D 透视设定 (perspective: 500px)
    CATransform3D perspective = CATransform3DIdentity;
    perspective.m34 = -1.0 / 500.0;
    self.trackContainer.layer.sublayerTransform = perspective;
    [self addSubview:self.trackContainer];

    // Track 视图 (overflow: hidden, border-radius: 50px)
    self.trackView = [[UIView alloc] initWithFrame:self.trackContainer.bounds];
    self.trackView.layer.cornerRadius = trackHeight / 2.0;
    self.trackView.layer.masksToBounds = YES;
    self.trackView.layer.shadowColor = [UIColor blackColor].CGColor;
    self.trackView.layer.shadowOffset = CGSizeMake(0, 4);
    self.trackView.layer.shadowRadius = 8;
    self.trackView.layer.shadowOpacity = 0.1;
    [self.trackContainer addSubview:self.trackView];

    // ============ 背景渐变层 ============
    self.dayBgView = [[UIView alloc] initWithFrame:self.trackView.bounds];
    self.dayGradLayer = [self createGradientWithColor1:0x87ceeb color2:0xe0f6ff];
    [self.dayBgView.layer addSublayer:self.dayGradLayer];
    [self.trackView addSubview:self.dayBgView];

    self.dayHoverBgView = [[UIView alloc] initWithFrame:self.trackView.bounds];
    self.dayHoverGradLayer = [self createGradientWithColor1:0x64b5f6 color2:0xe3f2fd];
    [self.dayHoverBgView.layer addSublayer:self.dayHoverGradLayer];
    self.dayHoverBgView.alpha = 0.0;
    [self.trackView addSubview:self.dayHoverBgView];

    self.nightBgView = [[UIView alloc] initWithFrame:self.trackView.bounds];
    self.nightGradLayer = [self createGradientWithColor1:0x1a237e color2:0x3949ab];
    [self.nightBgView.layer addSublayer:self.nightGradLayer];
    self.nightBgView.alpha = 0.0;
    [self.trackView addSubview:self.nightBgView];

    self.nightHoverBgView = [[UIView alloc] initWithFrame:self.trackView.bounds];
    self.nightHoverGradLayer = [self createGradientWithColor1:0x283593 color2:0x5c6bc0];
    [self.nightHoverBgView.layer addSublayer:self.nightHoverGradLayer];
    self.nightHoverBgView.alpha = 0.0;
    [self.trackView addSubview:self.nightHoverBgView];

    // ============ 星星 ============
    CGFloat starSize = 4.0;
    self.star1 = [[UIView alloc] initWithFrame:CGRectMake(trackWidth * 0.3, trackHeight * 0.2, starSize, starSize)];
    self.star1.backgroundColor = [UIColor whiteColor];
    self.star1.layer.cornerRadius = starSize / 2.0;
    self.star1.alpha = 0;
    [self.trackView addSubview:self.star1];

    self.star2 = [[UIView alloc] initWithFrame:CGRectMake(trackWidth * 0.75 - starSize, trackHeight * 0.75 - starSize, starSize, starSize)];
    self.star2.backgroundColor = [UIColor whiteColor];
    self.star2.layer.cornerRadius = starSize / 2.0;
    self.star2.alpha = 0;
    [self.trackView addSubview:self.star2];

    // ============ 滑块层 ============
    CGFloat knobDia = 2.4 * _em;
    // 初始位置: left 0.3em, top 0.3em
    self.knobContainer = [[UIView alloc] initWithFrame:CGRectMake(0.3 * _em, 0.3 * _em, knobDia, knobDia)];
    self.knobContainer.layer.shadowColor = [UIColor blackColor].CGColor;
    self.knobContainer.layer.shadowOffset = CGSizeMake(0, 2);
    self.knobContainer.layer.shadowRadius = 4;
    self.knobContainer.layer.shadowOpacity = 0.2;
    [self.trackContainer addSubview:self.knobContainer]; // 注意：滑块放在不裁剪的 container 中，云朵才能突破边界

    // 太阳光晕 (外置，不受翻转影响)
    self.sunGlowView = [[UIView alloc] initWithFrame:self.knobContainer.bounds];
    self.sunGlowView.backgroundColor = [UIColor clearColor];
    self.sunGlowView.layer.cornerRadius = knobDia / 2.0;
    self.sunGlowView.layer.shadowColor = ColorHex(0xffd700).CGColor;
    self.sunGlowView.layer.shadowOffset = CGSizeZero;
    self.sunGlowView.layer.shadowOpacity = 0.7;
    self.sunGlowView.layer.shadowRadius = 0;
    [self.knobContainer addSubview:self.sunGlowView];

    // 月亮光晕 (外置，不受翻转影响)
    self.moonGlowView = [[UIView alloc] initWithFrame:self.knobContainer.bounds];
    self.moonGlowView.backgroundColor = [UIColor clearColor];
    self.moonGlowView.layer.cornerRadius = knobDia / 2.0;
    self.moonGlowView.layer.shadowColor = [UIColor whiteColor].CGColor;
    self.moonGlowView.layer.shadowOffset = CGSizeZero;
    self.moonGlowView.layer.shadowOpacity = 0.5;
    self.moonGlowView.layer.shadowRadius = 20;
    self.moonGlowView.alpha = 0;
    [self.knobContainer addSubview:self.moonGlowView];

    // 滑块背景本体 (裁剪内阴影)
    self.knobBaseView = [[UIView alloc] initWithFrame:self.knobContainer.bounds];
    self.knobBaseView.backgroundColor = ColorHex(0xffd700);
    self.knobBaseView.layer.cornerRadius = knobDia / 2.0;
    self.knobBaseView.layer.masksToBounds = YES;
    [self.knobContainer addSubview:self.knobBaseView];

    // 月亮内阴影 (CSS: inset -10px -5px 0 0 #ddd)
    // 实现：一个 #ddd 的圆圈，向右下偏移，由于父视图 masksToBounds，左上方露出白色底色，形成完美的月牙
    self.moonInsetShadow = [[UIView alloc] initWithFrame:self.knobBaseView.bounds];
    self.moonInsetShadow.backgroundColor = ColorHex(0xdddddd);
    self.moonInsetShadow.layer.cornerRadius = knobDia / 2.0;
    self.moonInsetShadow.alpha = 0; // 默认白天隐藏
    [self.knobBaseView addSubview:self.moonInsetShadow];

    // ============ 形变伪元素 (云朵/陨石坑) ============
    self.pseudoElementBefore = [[UIView alloc] init];
    self.pseudoElementBefore.backgroundColor = ColorHexA(0xffffff, 0.8);
    [self.knobContainer addSubview:self.pseudoElementBefore];

    self.pseudoElementAfter = [[UIView alloc] init];
    self.pseudoElementAfter.backgroundColor = ColorHexA(0xffffff, 0.8);
    [self.knobContainer addSubview:self.pseudoElementAfter];

    [self layoutForCurrentStateAnimated:NO];

    // 手势
    UITapGestureRecognizer *tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapGestureOccurred:)];
    tapGesture.cancelsTouchesInView = NO;
    [self addGestureRecognizer:tapGesture];

    UIPanGestureRecognizer *panGesture = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(panGestureOccurred:)];
    panGesture.cancelsTouchesInView = NO;
    [self addGestureRecognizer:panGesture];
}

- (CAGradientLayer *)createGradientWithColor1:(NSInteger)hex1 color2:(NSInteger)hex2 {
    CAGradientLayer *grad = [CAGradientLayer layer];
    grad.frame = self.trackView.bounds;
    grad.colors = @[(id)ColorHex(hex1).CGColor, (id)ColorHex(hex2).CGColor];
    grad.startPoint = CGPointMake(0, 0.5);
    grad.endPoint = CGPointMake(1, 0.5);
    return grad;
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    if (self.window) {
        [self startAllLoopingAnimations];
    }
}

// ================== 无限循环动画 ==================
- (void)startAllLoopingAnimations {
    // 太阳脉冲 @keyframes sunPulse
    [self.sunGlowView.layer removeAllAnimations];
    CABasicAnimation *sunPulse = [CABasicAnimation animationWithKeyPath:@"shadowRadius"];
    sunPulse.fromValue = @0;
    sunPulse.toValue = @20; // 对应 CSS 20px
    sunPulse.duration = 1.5; // CSS 是 3s infinite，单程 1.5s
    sunPulse.autoreverses = YES;
    sunPulse.repeatCount = HUGE_VALF;
    [self.sunGlowView.layer addAnimation:sunPulse forKey:@"sunPulse"];

    // 月球呼吸 @keyframes moonPhase (内阴影变化)
    [self.moonInsetShadow.layer removeAllAnimations];
    CABasicAnimation *moonBreathX = [CABasicAnimation animationWithKeyPath:@"transform.translation.x"];
    moonBreathX.fromValue = @(0.5 * _em);  // 对应 -10px
    moonBreathX.toValue = @(0.0);          // 对应 0px
    CABasicAnimation *moonBreathY = [CABasicAnimation animationWithKeyPath:@"transform.translation.y"];
    moonBreathY.fromValue = @(0.25 * _em); // 对应 -5px
    moonBreathY.toValue = @(0.0);
    CAAnimationGroup *moonGroup = [CAAnimationGroup animation];
    moonGroup.animations = @[moonBreathX, moonBreathY];
    moonGroup.duration = 2.5; // CSS 是 5s infinite
    moonGroup.autoreverses = YES;
    moonGroup.repeatCount = HUGE_VALF;
    [self.moonInsetShadow.layer addAnimation:moonGroup forKey:@"moonPhase"];

    // 星星闪烁 @keyframes twinkle
    [self.star1.layer removeAllAnimations];
    CABasicAnimation *starAnim1 = [CABasicAnimation animationWithKeyPath:@"opacity"];
    starAnim1.fromValue = @0.2;
    starAnim1.toValue = @1.0;
    starAnim1.duration = 1.0;
    starAnim1.autoreverses = YES;
    starAnim1.repeatCount = HUGE_VALF;
    starAnim1.timeOffset = 0.5; // 对应 animation-delay: 0.5s
    [self.star1.layer addAnimation:starAnim1 forKey:@"twinkle"];

    [self.star2.layer removeAllAnimations];
    CABasicAnimation *starAnim2 = [CABasicAnimation animationWithKeyPath:@"opacity"];
    starAnim2.fromValue = @0.2;
    starAnim2.toValue = @1.0;
    starAnim2.duration = 1.0;
    starAnim2.autoreverses = YES;
    starAnim2.repeatCount = HUGE_VALF;
    [self.star2.layer addAnimation:starAnim2 forKey:@"twinkle"];
}

// ================== 手势处理 ==================
- (void)tapGestureOccurred:(UITapGestureRecognizer *)sender {
    if (self.isDragging) return;
    self.dragging = YES;
    [self setOn:!self.isOn animated:YES];
    self.dragging = NO;
}

- (void)panGestureOccurred:(UIPanGestureRecognizer *)sender {
    CGPoint touchLocation = [sender locationInView:self];
    if (sender.state == UIGestureRecognizerStateBegan) {
        self.onBeforeDrag = self.isOn;
        self.dragging = YES;
        self.hovering = YES;
        [self animateHoverState];
    } else if (sender.state == UIGestureRecognizerStateChanged) {
        self.moved = YES;
        if (touchLocation.x > self.bounds.size.width / 2 && !self.isOn) {
            [self setOn:YES animated:YES];
        } else if (touchLocation.x < self.bounds.size.width / 2 && self.isOn) {
            [self setOn:NO animated:YES];
        }
    } else if (sender.state == UIGestureRecognizerStateEnded || sender.state == UIGestureRecognizerStateCancelled || sender.state == UIGestureRecognizerStateFailed) {
        self.dragging = NO;
        self.moved = NO;
        self.hovering = NO;
        [self animateHoverState];
    }
}

// ================== 核心动画与渲染引擎 ==================
- (void)setOn:(BOOL)on { [self setOn:on animated:NO]; }

- (void)setOn:(BOOL)on animated:(BOOL)animated {
    if (_on == on) return;
    _on = on;

    if (self.changeAction && !_shouldSkipChangeAction && animated) {
        self.changeAction(on, YES);
    }

    BOOL doAnimate = animated && _shouldAnimateImportant;

    if (doAnimate) {
        if (@available(iOS 10.0, *)) {
            // 【核心】1:1 注入 CSS 的三次贝塞尔曲线 cubic-bezier(0.68, -0.55, 0.265, 1.55)
            UICubicTimingParameters *timingParams = [[UICubicTimingParameters alloc] initWithControlPoint1:CGPointMake(0.68, -0.55) controlPoint2:CGPointMake(0.265, 1.55)];
            UIViewPropertyAnimator *animator = [[UIViewPropertyAnimator alloc] initWithDuration:0.6 timingParameters:timingParams];
            [animator addAnimations:^{
                [self layoutForCurrentStateAnimated:YES];
            }];
            [animator startAnimation];
        } else {
            [UIView animateWithDuration:0.6 delay:0.0 usingSpringWithDamping:0.7 initialSpringVelocity:0.5 options:UIViewAnimationOptionCurveEaseInOut animations:^{
                [self layoutForCurrentStateAnimated:YES];
            } completion:nil];
        }
    } else {
        [self layoutForCurrentStateAnimated:NO];
    }
}

- (void)animateHoverState {
    [UIView animateWithDuration:0.3 animations:^{
        if (self.isHovering) {
            self.dayHoverBgView.alpha = self.isOn ? 0.0 : 1.0;
            self.nightHoverBgView.alpha = self.isOn ? 1.0 : 0.0;
        } else {
            self.dayHoverBgView.alpha = 0.0;
            self.nightHoverBgView.alpha = 0.0;
            [self layoutForCurrentStateAnimated:NO];
        }
    }];
}

- (void)layoutForCurrentStateAnimated:(BOOL)animated {
    // 1. 背景层切换
    self.dayBgView.alpha = self.isOn ? 0.0 : 1.0;
    self.nightBgView.alpha = self.isOn ? 1.0 : 0.0;

    // 2. 星星淡入淡出
    CGFloat starAlpha = self.isOn ? 1.0 : 0.0;
    self.star1.alpha = starAlpha;
    self.star2.alpha = starAlpha;

    // 3. 滑块本体 3D 位移与翻转 (CSS: transform: translateX(3em) translateZ(5px) rotateY(180deg))
    CATransform3D transform = CATransform3DIdentity;
    if (self.isOn) {
        transform = CATransform3DTranslate(transform, 3.0 * _em, 0, 5.0);
        transform = CATransform3DRotate(transform, M_PI, 0, 1, 0); // 180度翻转
    } else {
        transform = CATransform3DTranslate(transform, 0, 0, 5.0);
    }
    self.knobContainer.layer.transform = transform;

    // 4. 颜色交替与光晕
    self.knobBaseView.backgroundColor = self.isOn ? ColorHex(0xffffff) : ColorHex(0xffd700);
    self.moonInsetShadow.alpha = self.isOn ? 1.0 : 0.0;
    self.sunGlowView.alpha = self.isOn ? 0.0 : 1.0;
    self.moonGlowView.alpha = self.isOn ? 1.0 : 0.0;

    // 5. CSS 伪元素图层级复用形变 (云朵 morph 成 陨石坑)
    if (!self.isOn) {
        // 白天模式：云朵
        self.pseudoElementBefore.frame = CGRectMake(-0.2 * _em, -0.5 * _em, 1.0 * _em, 1.0 * _em);
        self.pseudoElementBefore.layer.cornerRadius = 0.5 * _em;
        self.pseudoElementBefore.backgroundColor = ColorHexA(0xffffff, 0.8);

        // after: bottom: -0.6em (top 1.8em), right: -0.3em (left 1.5em)
        self.pseudoElementAfter.frame = CGRectMake(1.5 * _em, 1.8 * _em, 1.2 * _em, 1.2 * _em);
        self.pseudoElementAfter.layer.cornerRadius = 0.6 * _em;
        self.pseudoElementAfter.backgroundColor = ColorHexA(0xffffff, 0.8);
    } else {
        // 夜晚模式：陨石坑
        self.pseudoElementBefore.frame = CGRectMake(0.3 * _em, 0.3 * _em, 0.6 * _em, 0.6 * _em);
        self.pseudoElementBefore.layer.cornerRadius = 0.3 * _em;
        self.pseudoElementBefore.backgroundColor = ColorHexA(0x000000, 0.2);

        // after: bottom: 0.5em (top 1.5em), right: 0.5em (left 1.5em)
        self.pseudoElementAfter.frame = CGRectMake(1.5 * _em, 1.5 * _em, 0.4 * _em, 0.4 * _em);
        self.pseudoElementAfter.layer.cornerRadius = 0.2 * _em;
        self.pseudoElementAfter.backgroundColor = ColorHexA(0x000000, 0.15);
    }
}

// ================== 兼容 Tweak ==================
- (CGFloat)knobMargin { return 0.3 * _em; }
- (void)blockChangeActionAnimated:(BOOL)animated { _shouldSkipChangeAction = YES; }
- (void)unblockChangeAction { _shouldSkipChangeAction = NO; }
- (void)dns_disableAnimations { _shouldAnimateImportant = NO; }

@end
