//
//  BB8Switch.m
//  BB8Switch
//

#import "BB8Switch.h"

// 颜色宏定义
#define ColorHex(hexValue) [UIColor colorWithRed:((float)((hexValue & 0xFF0000) >> 16))/255.0 green:((float)((hexValue & 0xFF00) >> 8))/255.0 blue:((float)(hexValue & 0xFF))/255.0 alpha:1.0]
#define ColorHexA(hexValue, a) [UIColor colorWithRed:((float)((hexValue & 0xFF0000) >> 16))/255.0 green:((float)((hexValue & 0xFF00) >> 8))/255.0 blue:((float)(hexValue & 0xFF))/255.0 alpha:(a)]

#define ColorAccent   ColorHex(0xde7d2f) // BB-8 橙色
#define ColorBB8Bg    ColorHex(0xffffff) // BB-8 白色
#define ColorSand     ColorHex(0xb18d71) // 塔图因沙地
#define ColorShadow   ColorHexA(0x3a271c, 0.4) // 阴影

@interface BB8Switch ()

// 背景层
@property (nonatomic, strong) UIView *trackView;
@property (nonatomic, strong) UIView *dayBgView;
@property (nonatomic, strong) UIView *nightBgView;
@property (nonatomic, strong) UIView *sandFloorView;

// 天体层
@property (nonatomic, strong) UIView *sun1;
@property (nonatomic, strong) UIView *sun2;
@property (nonatomic, strong) UIView *moon1;
@property (nonatomic, strong) UIView *moon2;
@property (nonatomic, strong) UIView *moon3;
@property (nonatomic, strong) UIView *starsContainer;

// BB-8 机器人组件
@property (nonatomic, strong) UIView *bb8Container;        // 主体容器 (顶层不裁切)
@property (nonatomic, strong) UIView *bb8ShadowContainer;  // 阴影容器 (底层被裁切)
@property (nonatomic, strong) UIView *bb8Shadow;
@property (nonatomic, strong) UIView *bb8Body;
@property (nonatomic, strong) UIView *bb8HeadContainer;
@property (nonatomic, strong) UIView *bb8Head;

@property (nonatomic, assign) CGFloat scale; // 响应式缩放系数

@property (nonatomic, assign, getter=isMoved) BOOL moved;
@property (nonatomic, assign, getter=isDragging) BOOL dragging;
@property (nonatomic, assign, getter=isOnBeforeDrag) BOOL onBeforeDrag;
@property (nonatomic, assign, getter=isHovering) BOOL hovering;

@end

@implementation BB8Switch {
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
    // 确保整个控件允许突破边界
    self.clipsToBounds = NO;

    _on = NO;
    _hovering = NO;
    self.moved = NO;
    self.dragging = NO;
    _shouldAnimateImportant = YES;

    // 基准设计高度设定为 90.0
    _scale = self.bounds.size.height / 90.0;

    // 1. 轨道视图 (限制背景和阴影不越界)
    self.trackView = [[UIView alloc] initWithFrame:self.bounds];
    self.trackView.layer.cornerRadius = self.bounds.size.height / 2.0;
    self.trackView.layer.masksToBounds = YES;
    [self addSubview:self.trackView];

    // 2. 白天天空
    self.dayBgView = [[UIView alloc] initWithFrame:self.bounds];
    CAGradientLayer *dayGrad = [CAGradientLayer layer];
    dayGrad.frame = self.bounds;
    dayGrad.colors = @[(id)ColorHex(0x628cac).CGColor, (id)ColorHex(0xa6c5d4).CGColor];
    [self.dayBgView.layer addSublayer:dayGrad];
    [self.trackView addSubview:self.dayBgView];

    // 3. 夜晚天空
    self.nightBgView = [[UIView alloc] initWithFrame:self.bounds];
    self.nightBgView.alpha = 0;
    CAGradientLayer *nightGrad = [CAGradientLayer layer];
    nightGrad.frame = self.bounds;
    nightGrad.colors = @[(id)ColorHex(0x070e2b).CGColor, (id)ColorHex(0x2c4770).CGColor];
    [self.nightBgView.layer addSublayer:nightGrad];
    [self.trackView addSubview:self.nightBgView];

    // 4. 沙地地板 (底部 30%)
    CGFloat floorHeight = self.bounds.size.height * 0.3;
    self.sandFloorView = [[UIView alloc] initWithFrame:CGRectMake(0, self.bounds.size.height - floorHeight, self.bounds.size.width, floorHeight)];
    self.sandFloorView.backgroundColor = ColorSand;
    [self.trackView addSubview:self.sandFloorView];

    // 5. 天体布置 (双日 + 三月 + 群星)
    [self setupScenery];

    // 6. BB-8 机器人
    [self setupBB8];

    [self layoutForCurrentStateAnimated:NO];

    // 手势
    UITapGestureRecognizer *tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapGestureOccurred:)];
    tapGesture.cancelsTouchesInView = NO;
    [self addGestureRecognizer:tapGesture];

    UIPanGestureRecognizer *panGesture = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(panGestureOccurred:)];
    panGesture.cancelsTouchesInView = NO;
    [self addGestureRecognizer:panGesture];
}

// ================== 构建背景与天体 ==================
- (void)setupScenery {
    // 太阳 1 (白色)
    self.sun1 = [[UIView alloc] initWithFrame:CGRectMake(self.bounds.size.width * 0.45, 10*_scale, 20*_scale, 20*_scale)];
    self.sun1.backgroundColor = ColorHex(0xfdf4e1);
    self.sun1.layer.cornerRadius = 10*_scale;
    [self.trackView insertSubview:self.sun1 belowSubview:self.sandFloorView];

    // 太阳 2 (橙红)
    self.sun2 = [[UIView alloc] initWithFrame:CGRectMake(self.bounds.size.width * 0.2, 35*_scale, 20*_scale, 20*_scale)];
    self.sun2.backgroundColor = ColorHex(0xd75449);
    self.sun2.layer.cornerRadius = 10*_scale;
    [self.trackView insertSubview:self.sun2 belowSubview:self.sandFloorView];

    // 卫星 1, 2, 3 (夜晚升起)
    self.moon1 = [self createMoonWithDia:30*_scale];
    self.moon2 = [self createMoonWithDia:10*_scale];
    self.moon3 = [self createMoonWithDia:8*_scale];
    [self.trackView insertSubview:self.moon1 belowSubview:self.sandFloorView];
    [self.trackView insertSubview:self.moon2 belowSubview:self.sandFloorView];
    [self.trackView insertSubview:self.moon3 belowSubview:self.sandFloorView];

    // 群星
    self.starsContainer = [[UIView alloc] initWithFrame:self.bounds];
    self.starsContainer.alpha = 0;
    for (int i = 0; i < 8; i++) {
        CGFloat size = (arc4random_uniform(2) + 1) * 1.5 * _scale;
        UIView *star = [[UIView alloc] initWithFrame:CGRectMake(arc4random_uniform((int)self.bounds.size.width), arc4random_uniform((int)(self.bounds.size.height * 0.6)), size, size)];
        star.backgroundColor = [UIColor whiteColor];
        star.layer.cornerRadius = size / 2.0;
        [self.starsContainer addSubview:star];
    }
    [self.trackView insertSubview:self.starsContainer belowSubview:self.sandFloorView];
}

- (UIView *)createMoonWithDia:(CGFloat)dia {
    UIView *moon = [[UIView alloc] initWithFrame:CGRectMake(0, 0, dia, dia)];
    moon.backgroundColor = ColorHex(0x6e8ea2);
    moon.layer.cornerRadius = dia / 2.0;
    // 陨石坑修饰
    UIView *crater = [[UIView alloc] initWithFrame:CGRectMake(dia*0.2, dia*0.2, dia*0.25, dia*0.25)];
    crater.backgroundColor = ColorHexA(0x000000, 0.15);
    crater.layer.cornerRadius = dia*0.125;
    [moon addSubview:crater];
    return moon;
}

// ================== 构建 BB-8 ==================
- (void)setupBB8 {
    CGFloat bb8Dia = 70.0 * _scale;
    CGFloat offset = 10.0 * _scale;

    // ================= 阴影层分离 =================
    // 阴影容器放在 trackView 里，保证阴影就算偏转也不会超出开关圆角
    self.bb8ShadowContainer = [[UIView alloc] initWithFrame:CGRectMake(offset, (self.bounds.size.height - bb8Dia)/2.0, bb8Dia, bb8Dia)];
    [self.trackView addSubview:self.bb8ShadowContainer];

    self.bb8Shadow = [[UIView alloc] initWithFrame:CGRectMake(-bb8Dia*0.1, bb8Dia*0.8, bb8Dia*1.2, bb8Dia*0.2)];
    self.bb8Shadow.backgroundColor = ColorShadow;
    self.bb8Shadow.layer.cornerRadius = bb8Dia*0.1;
    [self.bb8ShadowContainer addSubview:self.bb8Shadow];

    // ================= 主体层提升 =================
    // 主容器放在最顶层的 self 里（因为 self.clipsToBounds = NO），这样脑袋就能探出去了！
    self.bb8Container = [[UIView alloc] initWithFrame:CGRectMake(offset, (self.bounds.size.height - bb8Dia)/2.0, bb8Dia, bb8Dia)];
    [self addSubview:self.bb8Container];

    // 身体 (滚轮)
    self.bb8Body = [[UIView alloc] initWithFrame:self.bb8Container.bounds];
    self.bb8Body.backgroundColor = ColorBB8Bg;
    self.bb8Body.layer.cornerRadius = bb8Dia / 2.0;
    self.bb8Body.layer.masksToBounds = YES;
    self.bb8Body.layer.borderWidth = 1.0;
    self.bb8Body.layer.borderColor = ColorHex(0xdddddd).CGColor;

    // 身体橙色花纹 (简化矢量版，确保自转可见)
    UIView *centerRing = [[UIView alloc] initWithFrame:CGRectMake(bb8Dia*0.2, bb8Dia*0.2, bb8Dia*0.6, bb8Dia*0.6)];
    centerRing.layer.cornerRadius = bb8Dia*0.3;
    centerRing.layer.borderWidth = 4.0 * _scale;
    centerRing.layer.borderColor = ColorAccent.CGColor;
    [self.bb8Body addSubview:centerRing];

    UIView *centerDot = [[UIView alloc] initWithFrame:CGRectMake(bb8Dia*0.4, bb8Dia*0.4, bb8Dia*0.2, bb8Dia*0.2)];
    centerDot.layer.cornerRadius = bb8Dia*0.1;
    centerDot.backgroundColor = ColorAccent;
    [self.bb8Body addSubview:centerDot];

    UIView *lineV = [[UIView alloc] initWithFrame:CGRectMake(bb8Dia*0.48, 0, bb8Dia*0.04, bb8Dia)];
    lineV.backgroundColor = ColorAccent;
    [self.bb8Body insertSubview:lineV belowSubview:centerRing];

    UIView *lineH = [[UIView alloc] initWithFrame:CGRectMake(0, bb8Dia*0.48, bb8Dia, bb8Dia*0.04)];
    lineH.backgroundColor = ColorAccent;
    [self.bb8Body insertSubview:lineH belowSubview:centerRing];

    [self.bb8Container addSubview:self.bb8Body];

    // 头部容器 (用于控制倾斜)
    CGFloat headW = 40.0 * _scale;
    CGFloat headH = 28.0 * _scale;
    self.bb8HeadContainer = [[UIView alloc] initWithFrame:CGRectMake((bb8Dia - headW)/2.0, -headH + 8*_scale, headW, headH)];
    // 设置锚点为底部中心，像不倒翁一样摇头
    self.bb8HeadContainer.layer.anchorPoint = CGPointMake(0.5, 1.0);
    self.bb8HeadContainer.frame = CGRectMake((bb8Dia - headW)/2.0, -headH + 8*_scale, headW, headH); // 补正 frame
    [self.bb8Container addSubview:self.bb8HeadContainer];

    // 头部本体
    self.bb8Head = [[UIView alloc] initWithFrame:self.bb8HeadContainer.bounds];
    self.bb8Head.backgroundColor = ColorBB8Bg;
    self.bb8Head.layer.cornerRadius = headW / 2.0;
    if (@available(iOS 11.0, *)) {
        self.bb8Head.layer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner;
    }
    self.bb8Head.layer.masksToBounds = YES;
    self.bb8Head.layer.borderWidth = 1.0;
    self.bb8Head.layer.borderColor = ColorHex(0xdddddd).CGColor;
    [self.bb8HeadContainer addSubview:self.bb8Head];

    // 头部细节：主眼(黑)、副眼(红)、底边灰条
    UIView *grayStrip = [[UIView alloc] initWithFrame:CGRectMake(0, headH - 6*_scale, headW, 6*_scale)];
    grayStrip.backgroundColor = [UIColor lightGrayColor];
    [self.bb8Head addSubview:grayStrip];

    UIView *mainEye = [[UIView alloc] initWithFrame:CGRectMake(headW*0.35, headH*0.2, headW*0.3, headW*0.3)];
    mainEye.backgroundColor = [UIColor blackColor];
    mainEye.layer.cornerRadius = headW*0.15;
    mainEye.layer.borderWidth = 1.0;
    mainEye.layer.borderColor = [UIColor grayColor].CGColor;
    [self.bb8Head addSubview:mainEye];

    UIView *subEye = [[UIView alloc] initWithFrame:CGRectMake(headW*0.7, headH*0.4, headW*0.12, headW*0.12)];
    subEye.backgroundColor = [UIColor redColor];
    subEye.layer.cornerRadius = headW*0.06;
    [self.bb8Head addSubview:subEye];

    // 天线
    UIView *antenna1 = [[UIView alloc] initWithFrame:CGRectMake(headW*0.5, -10*_scale, 1.5*_scale, 10*_scale)];
    antenna1.backgroundColor = [UIColor grayColor];
    [self.bb8HeadContainer insertSubview:antenna1 belowSubview:self.bb8Head];

    UIView *antenna2 = [[UIView alloc] initWithFrame:CGRectMake(headW*0.7, -6*_scale, 1.5*_scale, 6*_scale)];
    antenna2.backgroundColor = [UIColor grayColor];
    [self.bb8HeadContainer insertSubview:antenna2 belowSubview:self.bb8Head];
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
            UICubicTimingParameters *timingParams = [[UICubicTimingParameters alloc] initWithControlPoint1:CGPointMake(0.25, 1.2) controlPoint2:CGPointMake(0.5, 1.0)];
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
    [UIView animateWithDuration:0.3 animations:^{
        if (self.isHovering) {
            // 按压时，脑袋往后倾斜 (25度)
            CGFloat angle = self.isOn ? -25.0 : 25.0;
            self.bb8HeadContainer.transform = CGAffineTransformMakeRotation(angle * M_PI / 180.0);
        } else {
            // 松开恢复直立
            self.bb8HeadContainer.transform = CGAffineTransformIdentity;
            [self layoutForCurrentStateAnimated:NO];
        }
    }];
}

- (void)layoutForCurrentStateAnimated:(BOOL)animated {
    CGFloat bb8Dia = 70.0 * _scale;
    CGFloat offset = 10.0 * _scale;

    // 1. 背景切换
    self.dayBgView.alpha = self.isOn ? 0.0 : 1.0;
    self.nightBgView.alpha = self.isOn ? 1.0 : 0.0;
    self.starsContainer.alpha = self.isOn ? 1.0 : 0.0;
    self.sandFloorView.backgroundColor = self.isOn ? ColorHex(0x504e57) : ColorSand;

    // 2. 天体起落
    CGFloat h = self.bounds.size.height;
    self.sun1.frame = CGRectMake(self.bounds.size.width * 0.45, self.isOn ? h : 10*_scale, 20*_scale, 20*_scale);
    self.sun2.frame = CGRectMake(self.bounds.size.width * 0.2, self.isOn ? h : 35*_scale, 20*_scale, 20*_scale);

    self.moon1.frame = CGRectMake(15*_scale, self.isOn ? 15*_scale : h, 30*_scale, 30*_scale);
    self.moon2.frame = CGRectMake(self.bounds.size.width * 0.55, self.isOn ? 40*_scale : h, 10*_scale, 10*_scale);
    self.moon3.frame = CGRectMake(self.bounds.size.width * 0.7, self.isOn ? 45*_scale : h, 8*_scale, 8*_scale);

    // 3. BB-8 本体及阴影容器同步移动
    CGFloat targetX = self.isOn ? (self.bounds.size.width - bb8Dia - offset) : offset;
    CGRect targetFrame = CGRectMake(targetX, (h - bb8Dia)/2.0, bb8Dia, bb8Dia);

    self.bb8Container.frame = targetFrame;
    self.bb8ShadowContainer.frame = targetFrame;

    // 4. BB-8 身体滚动 (180度旋转)
    self.bb8Body.transform = self.isOn ? CGAffineTransformMakeRotation(M_PI * 0.999) : CGAffineTransformIdentity;

    // 5. 阴影 SkewX 偏转
    CGFloat skewAngle = self.isOn ? (45.0 * M_PI / 180.0) : (-45.0 * M_PI / 180.0);
    CGAffineTransform skewTransform = CGAffineTransformMake(1, 0, tan(skewAngle), 1, 0, 0);
    self.bb8Shadow.transform = skewTransform;
}

// ================== 兼容 Tweak ==================
- (CGFloat)knobMargin { return 10.0 * _scale; }
- (void)blockChangeActionAnimated:(BOOL)animated { _shouldSkipChangeAction = YES; }
- (void)unblockChangeAction { _shouldSkipChangeAction = NO; }
- (void)dns_disableAnimations { _shouldAnimateImportant = NO; }

@end
