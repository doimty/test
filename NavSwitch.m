//
//  NavSwitch.m
//  NavSwitch
//

#import "NavSwitch.h"

// 颜色宏定义
#define ColorHex(hexValue) [UIColor colorWithRed:((float)((hexValue & 0xFF0000) >> 16))/255.0 green:((float)((hexValue & 0xFF00) >> 8))/255.0 blue:((float)(hexValue & 0xFF))/255.0 alpha:1.0]
#define ColorHexA(hexValue, a) [UIColor colorWithRed:((float)((hexValue & 0xFF0000) >> 16))/255.0 green:((float)((hexValue & 0xFF00) >> 8))/255.0 blue:((float)(hexValue & 0xFF))/255.0 alpha:(a)]

#define ColorBgOff ColorHex(0xc7dbd7) // rgb(199, 219, 215)
#define ColorBgOn  ColorHex(0x2b4360) // #2b4360

@interface NavSwitch ()

@property (nonatomic, strong) UIView *trackContainer;
@property (nonatomic, strong) UIView *trackView;

// 引航标组件
@property (nonatomic, strong) UIView *navContainer; // 负责 translateX 平移
@property (nonatomic, strong) UIView *navIconView;  // 负责 rotate(45deg) 和 绘制形状

// 星星组件
@property (nonatomic, strong) UIView *star1;
@property (nonatomic, strong) UIView *star2;
@property (nonatomic, strong) UIView *star3;
@property (nonatomic, strong) UIView *star4;

@property (nonatomic, assign) CGFloat em;

@property (nonatomic, assign, getter=isMoved) BOOL moved;
@property (nonatomic, assign, getter=isDragging) BOOL dragging;
@property (nonatomic, assign, getter=isOnBeforeDrag) BOOL onBeforeDrag;
@property (nonatomic, assign, getter=isHovering) BOOL hovering;

@end

@implementation NavSwitch {
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

    // CSS 比例：高度 2em，宽度 3.5em。
    _em = self.bounds.size.height / 2.0;
    CGFloat trackWidth = 3.5 * _em;
    CGFloat trackHeight = 2.0 * _em;

    // 居中容器
    self.trackContainer = [[UIView alloc] initWithFrame:CGRectMake((self.bounds.size.width - trackWidth)/2.0, (self.bounds.size.height - trackHeight)/2.0, trackWidth, trackHeight)];
    [self addSubview:self.trackContainer];

    // 1. 轨道背景
    self.trackView = [[UIView alloc] initWithFrame:self.trackContainer.bounds];
    self.trackView.backgroundColor = ColorBgOff;
    self.trackView.layer.cornerRadius = trackHeight / 2.0; // border-radius: 30px
    self.trackView.layer.borderWidth = 1.0;
    self.trackView.layer.borderColor = [UIColor whiteColor].CGColor;
    self.trackView.layer.shadowColor = [UIColor blackColor].CGColor;
    self.trackView.layer.shadowOffset = CGSizeMake(0, 4);
    self.trackView.layer.shadowRadius = 8;
    self.trackView.layer.shadowOpacity = 0.1;
    [self.trackContainer addSubview:self.trackView];

    // 2. 星星 (精确对应 CSS 的位置)
    self.star1 = [self createStarWithX:13 y:7];
    self.star2 = [self createStarWithX:19 y:14];
    self.star3 = [self createStarWithX:9  y:18];
    self.star4 = [self createStarWithX:24 y:23];

    // 3. 导航标平移容器
    self.navContainer = [[UIView alloc] initWithFrame:CGRectMake(0.3 * _em, 0.3 * _em, 1.5 * _em, 1.4 * _em)];
    [self.trackView addSubview:self.navContainer];

    // ==========================================
    // 4. 极简导航标/纸飞机 (完美还原 CSS 效果)
    // ==========================================
    self.navIconView = [[UIView alloc] initWithFrame:self.navContainer.bounds];

    // 完美复刻 CSS: transform: rotate(45deg);
    self.navIconView.transform = CGAffineTransformMakeRotation(45.0 * M_PI / 180.0);
    [self.navContainer addSubview:self.navIconView];

    // 使用贝塞尔曲线画出经典的锋利导航箭头
    CAShapeLayer *navLayer = [CAShapeLayer layer];
    navLayer.frame = self.navIconView.bounds;
    navLayer.fillColor = [UIColor whiteColor].CGColor; // fill: #fff;

    CGFloat w = self.navIconView.bounds.size.width;
    CGFloat h = self.navIconView.bounds.size.height;

    UIBezierPath *path = [UIBezierPath bezierPath];
    [path moveToPoint:CGPointMake(w * 0.5, 0)];           // 顶点 (尖端)
    [path addLineToPoint:CGPointMake(w, h)];              // 右下角
    [path addLineToPoint:CGPointMake(w * 0.5, h * 0.75)]; // 底部中心凹槽 (形成燕尾)
    [path addLineToPoint:CGPointMake(0, h)];              // 左下角
    [path closePath]; // 闭合路径

    navLayer.path = path.CGPath;
    [self.navIconView.layer addSublayer:navLayer];

    [self layoutForCurrentStateAnimated:NO];

    // 手势
    UITapGestureRecognizer *tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapGestureOccurred:)];
    tapGesture.cancelsTouchesInView = NO;
    [self addGestureRecognizer:tapGesture];

    UIPanGestureRecognizer *panGesture = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(panGestureOccurred:)];
    panGesture.cancelsTouchesInView = NO;
    [self addGestureRecognizer:panGesture];
}

// 基于 34px 高度的比例换算星星位置
- (UIView *)createStarWithX:(CGFloat)x y:(CGFloat)y {
    CGFloat scale = (2.0 * _em) / 34.0;
    UIView *star = [[UIView alloc] initWithFrame:CGRectMake(x * scale, y * scale, 2.0 * scale, 2.0 * scale)];
    star.backgroundColor = [UIColor whiteColor];
    star.layer.cornerRadius = 1.0 * scale;
    star.alpha = 0;
    [self.trackView addSubview:star];
    return star;
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    if (self.window) {
        [self startAllLoopingAnimations];
    }
}

// ================== 无限循环动画 ==================
- (void)startAllLoopingAnimations {
    [self.navContainer.layer removeAllAnimations];
    [self.star1.layer removeAllAnimations];
    [self.star2.layer removeAllAnimations];
    [self.star3.layer removeAllAnimations];
    [self.star4.layer removeAllAnimations];

    if (self.isOn) {
        // 1. 引航标试探动画: translateX 原汁原味曲线 (保持内层 45 度旋转不受影响)
        CAKeyframeAnimation *navWiggle = [CAKeyframeAnimation animationWithKeyPath:@"transform.translation.x"];
        navWiggle.values = @[
            @(1.3 * _em),
            @(1.1 * _em),
            @(1.2 * _em),
            @(1.0 * _em),
            @(1.2 * _em),
            @(1.0 * _em),
            @(1.2 * _em),
            @(1.3 * _em)
        ];
        navWiggle.keyTimes = @[@0, @0.1, @0.3, @0.5, @0.7, @0.8, @0.9, @1.0];
        navWiggle.duration = 4.0;
        navWiggle.repeatCount = HUGE_VALF;
        [self.navContainer.layer addAnimation:navWiggle forKey:@"navWiggle"];

        // 2. 星星闪烁动画
        CABasicAnimation *blink = [CABasicAnimation animationWithKeyPath:@"opacity"];
        blink.fromValue = @1.0;
        blink.toValue = @0.0;
        blink.duration = 1.0;
        blink.autoreverses = YES;
        blink.repeatCount = HUGE_VALF;

        [self.star1.layer addAnimation:blink forKey:@"piscar"];
        [self.star2.layer addAnimation:blink forKey:@"piscar"];
        [self.star3.layer addAnimation:blink forKey:@"piscar"];
        [self.star4.layer addAnimation:blink forKey:@"piscar"];
    }
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
        [UIView animateWithDuration:0.4 delay:0.0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
            [self layoutForCurrentStateAnimated:YES];
        } completion:^(BOOL finished) {
            if (finished) {
                [self startAllLoopingAnimations];
            }
        }];
    } else {
        [self layoutForCurrentStateAnimated:NO];
        [self startAllLoopingAnimations];
    }
}

- (void)animateHoverState {
    [UIView animateWithDuration:0.3 animations:^{
        if (self.isHovering) {
            self.trackView.transform = CGAffineTransformMakeScale(0.95, 0.95);
        } else {
            self.trackView.transform = CGAffineTransformIdentity;
            [self layoutForCurrentStateAnimated:NO];
        }
    }];
}

- (void)layoutForCurrentStateAnimated:(BOOL)animated {
    // 1. 轨道背景色
    self.trackView.backgroundColor = self.isOn ? ColorBgOn : ColorBgOff;

    // 2. 引航标平移
    CGFloat targetX = self.isOn ? (1.3 * _em) : 0;
    self.navContainer.transform = CGAffineTransformMakeTranslation(targetX, 0);

    // 3. 星星显示状态
    CGFloat starAlpha = self.isOn ? 1.0 : 0.0;
    self.star1.alpha = starAlpha;
    self.star2.alpha = starAlpha;
    self.star3.alpha = starAlpha;
    self.star4.alpha = starAlpha;

    if (!self.isOn) {
        [self.navContainer.layer removeAllAnimations];
        [self.star1.layer removeAllAnimations];
        [self.star2.layer removeAllAnimations];
        [self.star3.layer removeAllAnimations];
        [self.star4.layer removeAllAnimations];
    }
}

// ================== 兼容 Tweak ==================
- (CGFloat)knobMargin { return 0.3 * _em; }
- (void)blockChangeActionAnimated:(BOOL)animated { _shouldSkipChangeAction = YES; }
- (void)unblockChangeAction { _shouldSkipChangeAction = NO; }

@end
