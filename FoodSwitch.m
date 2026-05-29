//
//  FoodSwitch.m
//  FoodSwitch
//

#import "FoodSwitch.h"

// CSS 颜色宏映射
#define ColorBgBurger    [UIColor colorWithRed:255/255.0 green:236/255.0 blue:210/255.0 alpha:1.0] // #ffecd2
#define ColorBgFries     [UIColor colorWithRed:255/255.0 green:245/255.0 blue:230/255.0 alpha:1.0] // #fff5e6
#define ColorOutline     [UIColor colorWithRed:51/255.0 green:51/255.0 blue:51/255.0 alpha:1.0]    // #333333
#define ColorBun         [UIColor colorWithRed:255/255.0 green:166/255.0 blue:77/255.0 alpha:1.0]  // #ffa64d
#define ColorLettuce     [UIColor colorWithRed:140/255.0 green:214/255.0 blue:94/255.0 alpha:1.0]  // #8cd65e
#define ColorPatty       [UIColor colorWithRed:139/255.0 green:69/255.0 blue:19/255.0 alpha:1.0]   // #8b4513
#define ColorFryBox      [UIColor colorWithRed:255/255.0 green:71/255.0 blue:87/255.0 alpha:1.0]   // #ff4757
#define ColorFry         [UIColor colorWithRed:255/255.0 green:211/255.0 blue:42/255.0 alpha:1.0]  // #ffd32a

@interface FoodSwitch ()

@property (nonatomic, strong) UIView *trackContainer;
@property (nonatomic, strong) UIView *trackView;
@property (nonatomic, strong) UIView *knobWrapper;

// 汉堡组件
@property (nonatomic, strong) UIView *burgerContainer;
@property (nonatomic, strong) UIView *bunTop;
@property (nonatomic, strong) UIView *lettuce;
@property (nonatomic, strong) UIView *patty;
@property (nonatomic, strong) UIView *bunBottom;

// 薯条 3D 组件
@property (nonatomic, strong) UIView *friesContainer;
@property (nonatomic, strong) UIView *friesXRotator; // 承载 rotateX(-20deg)
@property (nonatomic, strong) UIView *friesYRotator; // 承载 360度动画

@property (nonatomic, assign) CGFloat scale; // 全局缩放比例

@property (nonatomic, assign, getter=isMoved) BOOL moved;
@property (nonatomic, assign, getter=isDragging) BOOL dragging;
@property (nonatomic, assign, getter=isOnBeforeDrag) BOOL onBeforeDrag;
@property (nonatomic, assign, getter=isHovering) BOOL hovering;

@end

@implementation FoodSwitch {
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

    // CSS 比例：高度是 60，宽度 120。以此为基准进行响应式缩放
    _scale = self.bounds.size.height / 60.0;
    CGFloat w = 120.0 * _scale;
    CGFloat h = 60.0 * _scale;
    CGFloat borderW = 3.0 * _scale;

    // 居中容器
    self.trackContainer = [[UIView alloc] initWithFrame:CGRectMake((self.bounds.size.width - w)/2.0, (self.bounds.size.height - h)/2.0, w, h)];
    [self addSubview:self.trackContainer];

    // 1. 背景轨道
    self.trackView = [[UIView alloc] initWithFrame:self.trackContainer.bounds];
    self.trackView.backgroundColor = ColorBgBurger;
    self.trackView.layer.cornerRadius = 60.0 * _scale / 2.0;
    self.trackView.layer.borderWidth = borderW;
    self.trackView.layer.borderColor = ColorOutline.CGColor;
    self.trackView.layer.masksToBounds = YES;
    [self.trackContainer addSubview:self.trackView];

    // 2. 滑块 Wrapper
    CGFloat offset = 5.0 * _scale;
    CGFloat knobSize = 50.0 * _scale;
    self.knobWrapper = [[UIView alloc] initWithFrame:CGRectMake(offset, offset, knobSize, knobSize)];
    [self.trackContainer addSubview:self.knobWrapper];

    // ====== 3. 构建 2D 汉堡 ======
    self.burgerContainer = [[UIView alloc] initWithFrame:CGRectMake((knobSize - 40*_scale)/2.0, (knobSize - 40*_scale)/2.0, 40*_scale, 40*_scale)];
    [self.knobWrapper addSubview:self.burgerContainer];

    CGFloat outlineW = 2.0 * _scale;

    // 顶层面包
    self.bunTop = [[UIView alloc] initWithFrame:CGRectMake((40-36)*_scale/2.0, 2*_scale, 36*_scale, 16*_scale)];
    self.bunTop.backgroundColor = ColorBun;
    self.bunTop.layer.borderWidth = outlineW;
    self.bunTop.layer.borderColor = ColorOutline.CGColor;
    self.bunTop.layer.cornerRadius = 16*_scale;
    if (@available(iOS 11.0, *)) {
        self.bunTop.layer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner;
    }
    self.bunTop.layer.zPosition = 4;
    [self.burgerContainer addSubview:self.bunTop];

    // 芝麻 (3个黑点)
    UIView *seed1 = [[UIView alloc] initWithFrame:CGRectMake(10*_scale, 6*_scale, 2*_scale, 2*_scale)];
    seed1.backgroundColor = ColorOutline; seed1.layer.cornerRadius = 1*_scale;
    [self.bunTop addSubview:seed1];
    UIView *seed2 = [[UIView alloc] initWithFrame:CGRectMake(22*_scale, 6*_scale, 2*_scale, 2*_scale)];
    seed2.backgroundColor = ColorOutline; seed2.layer.cornerRadius = 1*_scale;
    [self.bunTop addSubview:seed2];
    UIView *seed3 = [[UIView alloc] initWithFrame:CGRectMake(16*_scale, 10*_scale, 2*_scale, 2*_scale)];
    seed3.backgroundColor = ColorOutline; seed3.layer.cornerRadius = 1*_scale;
    [self.bunTop addSubview:seed3];

    // 生菜
    self.lettuce = [[UIView alloc] initWithFrame:CGRectMake(0, 16*_scale, 40*_scale, 6*_scale)];
    self.lettuce.backgroundColor = ColorLettuce;
    self.lettuce.layer.borderWidth = outlineW;
    self.lettuce.layer.borderColor = ColorOutline.CGColor;
    self.lettuce.layer.cornerRadius = 3*_scale;
    self.lettuce.layer.zPosition = 3;
    [self.burgerContainer addSubview:self.lettuce];

    // 肉饼
    self.patty = [[UIView alloc] initWithFrame:CGRectMake((40-36)*_scale/2.0, 20*_scale, 36*_scale, 8*_scale)];
    self.patty.backgroundColor = ColorPatty;
    self.patty.layer.borderWidth = outlineW;
    self.patty.layer.borderColor = ColorOutline.CGColor;
    self.patty.layer.cornerRadius = 4*_scale;
    self.patty.layer.zPosition = 2;
    [self.burgerContainer addSubview:self.patty];

    // 底层面包
    self.bunBottom = [[UIView alloc] initWithFrame:CGRectMake((40-36)*_scale/2.0, 26*_scale, 36*_scale, 10*_scale)];
    self.bunBottom.backgroundColor = ColorBun;
    self.bunBottom.layer.borderWidth = outlineW;
    self.bunBottom.layer.borderColor = ColorOutline.CGColor;
    self.bunBottom.layer.cornerRadius = 5*_scale;
    if (@available(iOS 11.0, *)) {
        self.bunBottom.layer.maskedCorners = kCALayerMinXMaxYCorner | kCALayerMaxXMaxYCorner;
    }
    self.bunBottom.layer.zPosition = 1;
    [self.burgerContainer addSubview:self.bunBottom];

    // ====== 4. 构建 3D 薯条 ======
    self.friesContainer = [[UIView alloc] initWithFrame:self.burgerContainer.frame];
    self.friesContainer.alpha = 0;

    // 赋予 3D 透视
    CATransform3D perspective = CATransform3DIdentity;
    perspective.m34 = -1.0 / 600.0;
    self.friesContainer.layer.sublayerTransform = perspective;
    [self.knobWrapper addSubview:self.friesContainer];

    // 倾斜容器 (对应 CSS: rotateX(-20deg) )
    self.friesXRotator = [[UIView alloc] initWithFrame:self.friesContainer.bounds];
    self.friesXRotator.layer.transform = CATransform3DMakeRotation(-20.0 * M_PI / 180.0, 1, 0, 0);
    [self.friesContainer addSubview:self.friesXRotator];

    // 旋转容器 (用于匀速 360度 spin)
    self.friesYRotator = [[UIView alloc] initWithFrame:self.friesContainer.bounds];
    [self.friesXRotator addSubview:self.friesYRotator];

    // 添加 3D 盒子的 5 个面 (宽高 30x35)
    [self addFryBoxFace:CATransform3DMakeTranslation(0, 0, 15*_scale) color:ColorFryBox]; // 前
    [self addFryBoxFace:CATransform3DTranslate(CATransform3DMakeRotation(M_PI, 0, 1, 0), 0, 0, 15*_scale) color:ColorFryBox]; // 后
    [self addFryBoxFace:CATransform3DTranslate(CATransform3DMakeRotation(M_PI_2, 0, 1, 0), 0, 0, 15*_scale) color:ColorFryBox]; // 右
    [self addFryBoxFace:CATransform3DTranslate(CATransform3DMakeRotation(-M_PI_2, 0, 1, 0), 0, 0, 15*_scale) color:ColorFryBox]; // 左

    // 底部 (30x30)
    UIView *bottomFace = [[UIView alloc] initWithFrame:CGRectMake(5*_scale, 5*_scale, 30*_scale, 30*_scale)];
    bottomFace.backgroundColor = ColorFryBox;
    bottomFace.layer.borderWidth = outlineW;
    bottomFace.layer.borderColor = ColorOutline.CGColor;
    bottomFace.layer.transform = CATransform3DTranslate(CATransform3DMakeRotation(-M_PI_2, 1, 0, 0), 0, 0, 30*_scale);
    [self.friesYRotator addSubview:bottomFace];

    // 添加散落的薯条 (设置锚点到底部，完美还原 transform-origin: bottom)
    [self addFryWithX:8 H:25 rotZ:-10 z:10 topOffset:0];   // f1
    [self addFryWithX:16 H:32 rotZ:0 z:5 topOffset:-7];    // f2
    [self addFryWithX:12 H:25 rotZ:8 z:-5 topOffset:0];    // f3
    [self addFryWithX:22 H:20 rotZ:10 z:10 topOffset:0];   // f4
    [self addFryWithX:8 H:28 rotZ:-15 z:-8 topOffset:-2];  // f5
    [self addFryWithX:24 H:24 rotZ:5 z:0 topOffset:0];     // f6
    [self addFryWithX:14 H:26 rotZ:-5 z:12 topOffset:2];   // f7

    [self layoutForCurrentStateAnimated:NO];

    // 添加手势
    UITapGestureRecognizer *tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapGestureOccurred:)];
    tapGesture.cancelsTouchesInView = NO;
    [self addGestureRecognizer:tapGesture];

    UIPanGestureRecognizer *panGesture = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(panGestureOccurred:)];
    panGesture.cancelsTouchesInView = YES;
    [self addGestureRecognizer:panGesture];
}

- (void)addFryBoxFace:(CATransform3D)transform color:(UIColor *)color {
    UIView *face = [[UIView alloc] initWithFrame:CGRectMake(5*_scale, 5*_scale, 30*_scale, 35*_scale)];
    face.backgroundColor = color;
    face.layer.borderWidth = 2.0 * _scale;
    face.layer.borderColor = ColorOutline.CGColor;
    face.layer.transform = transform;
    // backface-visibility: visible (iOS 默认开启)
    [self.friesYRotator addSubview:face];
}

- (void)addFryWithX:(CGFloat)x H:(CGFloat)h rotZ:(CGFloat)rz z:(CGFloat)z topOffset:(CGFloat)yOff {
    UIView *fry = [[UIView alloc] initWithFrame:CGRectMake(x*_scale, (-10+yOff)*_scale, 6*_scale, h*_scale)];
    fry.backgroundColor = ColorFry;
    fry.layer.borderWidth = 2.0 * _scale;
    fry.layer.borderColor = ColorOutline.CGColor;
    fry.layer.cornerRadius = 2.0 * _scale;
    // CSS: transform-origin: bottom
    fry.layer.anchorPoint = CGPointMake(0.5, 1.0);
    // 补正 anchor 偏移导致的 Y 轴位移
    fry.frame = CGRectMake(x*_scale, (-10+yOff)*_scale, 6*_scale, h*_scale);

    CATransform3D t = CATransform3DMakeTranslation(0, 0, z*_scale);
    t = CATransform3DRotate(t, rz * M_PI / 180.0, 0, 0, 1);
    fry.layer.transform = t;

    [self.friesYRotator addSubview:fry];
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    if (self.window) {
        [self startAllLoopingAnimations];
    }
}

// ================== 无限循环动画 ==================
- (void)startAllLoopingAnimations {
    // 薯条盒无休止旋转 @keyframes spinFries
    [self.friesYRotator.layer removeAllAnimations];
    CABasicAnimation *spin = [CABasicAnimation animationWithKeyPath:@"transform.rotation.y"];
    spin.fromValue = @(0);
    spin.toValue = @(2 * M_PI);
    spin.duration = 3.0;
    spin.repeatCount = HUGE_VALF;
    spin.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear];
    [self.friesYRotator.layer addAnimation:spin forKey:@"spinFries"];
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
            // CSS: transition: transform 0.5s cubic-bezier(0.175, 0.885, 0.32, 1.275);
            UICubicTimingParameters *timingParams = [[UICubicTimingParameters alloc] initWithControlPoint1:CGPointMake(0.175, 0.885) controlPoint2:CGPointMake(0.32, 1.275)];
            UIViewPropertyAnimator *animator = [[UIViewPropertyAnimator alloc] initWithDuration:0.5 timingParameters:timingParams];
            [animator addAnimations:^{
                [self layoutForCurrentStateAnimated:YES];
            }];
            [animator startAnimation];
        } else {
            [UIView animateWithDuration:0.5 delay:0.0 usingSpringWithDamping:0.7 initialSpringVelocity:0.5 options:UIViewAnimationOptionCurveEaseInOut animations:^{
                [self layoutForCurrentStateAnimated:YES];
            } completion:nil];
        }
    } else {
        [self layoutForCurrentStateAnimated:NO];
    }
}

- (void)animateHoverState {
    // 兼容原有的 Tweak 悬停交互，不强制影响 CSS 逻辑
    [UIView animateWithDuration:0.3 animations:^{
        if (self.isHovering) {
            self.knobWrapper.transform = CGAffineTransformMakeScale(0.9, 0.9);
        } else {
            self.knobWrapper.transform = CGAffineTransformIdentity;
            [self layoutForCurrentStateAnimated:NO];
        }
    }];
}

- (void)layoutForCurrentStateAnimated:(BOOL)animated {
    // 1. 轨道背景色
    self.trackView.backgroundColor = self.isOn ? ColorBgFries : ColorBgBurger;

    // 2. 滑块平移 (calc(var(--w) - var(--knob-size) - (var(--offset) * 2)))
    CGFloat offset = 5.0 * _scale;
    CGFloat knobSize = 50.0 * _scale;
    CGFloat targetX = self.isOn ? (120.0*_scale - knobSize - offset) : offset;
    self.knobWrapper.frame = CGRectMake(targetX, offset, knobSize, knobSize);

    // 3. 汉堡状态: opacity 0, scale(0), rotate(-90deg)
    CGAffineTransform burgerTransform = CGAffineTransformIdentity;
    if (self.isOn) {
        // scale(0) 会导致逆矩阵问题，使用 0.001 替代完美避开底层报错
        burgerTransform = CGAffineTransformScale(burgerTransform, 0.001, 0.001);
        burgerTransform = CGAffineTransformRotate(burgerTransform, -M_PI_2);
    }
    self.burgerContainer.transform = burgerTransform;
    self.burgerContainer.alpha = self.isOn ? 0.0 : 1.0;

    // 4. 薯条状态: opacity 1, scale(1) -> 初始隐藏缩放也是一样处理
    CGAffineTransform friesTransform = CGAffineTransformIdentity;
    if (!self.isOn) {
        friesTransform = CGAffineTransformScale(friesTransform, 0.001, 0.001);
    }
    self.friesContainer.transform = friesTransform;
    self.friesContainer.alpha = self.isOn ? 1.0 : 0.0;
}

// ================== 兼容 Tweak ==================
- (CGFloat)knobMargin { return 5.0 * _scale; }
- (void)blockChangeActionAnimated:(BOOL)animated { _shouldSkipChangeAction = YES; }
- (void)unblockChangeAction { _shouldSkipChangeAction = NO; }

@end
