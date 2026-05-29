//
//  DoggoSwitch.m
//  DoggoSwitch (终极细节优化版：解决漂移 + 修正短耳 + 右耳正向旋转)
//

#import "DoggoSwitch.h"

// 1:1 提取自原版 CSS 的颜色
#define ColorTrack    [UIColor colorWithRed:196/255.0 green:135/255.0 blue:222/255.0 alpha:1.0] // #c487de (浅紫)
#define ColorFace     [UIColor colorWithRed:255/255.0 green:255/255.0 blue:255/255.0 alpha:1.0] // #ffffff (白)
#define ColorEar      [UIColor colorWithRed:249/255.0 green:187/255.0 blue:0/255.0 alpha:1.0]   // #f9bb00 (黄)
#define ColorDark     [UIColor colorWithRed:34/255.0  green:34/255.0  blue:34/255.0  alpha:1.0] // #222222 (黑)
#define ColorPatch    [UIColor colorWithRed:228/255.0 green:172/255.0 blue:4/255.0   alpha:1.0] // #e4ac04 (眼贴斑)
#define ColorTongue   [UIColor colorWithRed:236/255.0 green:120/255.0 blue:141/255.0 alpha:1.0] // #ec788d (舌头粉)

@interface DoggoSwitch ()

@property (nonatomic, strong) UIView *trackContainer;
@property (nonatomic, strong) UIView *trackView;

// 【防漂移：物理隔离】
// 专门负责水平位移，绝不旋转
@property (nonatomic, strong) UIView *dogTransContainer;
// 专门负责 360 度自转，绝不平移
@property (nonatomic, strong) UIView *dogRotContainer;

@property (nonatomic, strong) UIView *leftEar;
@property (nonatomic, strong) UIView *rightEar;
@property (nonatomic, strong) UIView *faceView;
@property (nonatomic, strong) UIView *mouthContainer;

@property (nonatomic, assign) CGFloat em;
@property (nonatomic, assign, getter=isMoved) BOOL moved;
@property (nonatomic, assign, getter=isDragging) BOOL dragging;
@property (nonatomic, assign, getter=isOnBeforeDrag) BOOL onBeforeDrag;
@property (nonatomic, assign, getter=isHovering) BOOL hovering;

@end

@implementation DoggoSwitch {
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

    // 比例映射
    _em = self.bounds.size.height / 3.0;
    CGFloat trackWidth = 7.0 * _em;
    CGFloat trackHeight = 3.0 * _em;

    self.trackContainer = [[UIView alloc] initWithFrame:CGRectMake((self.bounds.size.width - trackWidth)/2.0, (self.bounds.size.height - trackHeight)/2.0, trackWidth, trackHeight)];
    [self addSubview:self.trackContainer];

    // 1. 轨道层
    self.trackView = [[UIView alloc] initWithFrame:self.trackContainer.bounds];
    self.trackView.backgroundColor = ColorTrack;
    self.trackView.layer.cornerRadius = trackHeight / 2.0;
    [self.trackContainer addSubview:self.trackView];

    // 2. 物理隔离双层容器
    // 平移层 (CSS: left 0.2em, top 0.25em)
    self.dogTransContainer = [[UIView alloc] initWithFrame:CGRectMake(0.2 * _em, 0.25 * _em, 2.5 * _em, 2.5 * _em)];
    [self.trackContainer addSubview:self.dogTransContainer];

    // 旋转层 (专职负责 360 度自转)
    self.dogRotContainer = [[UIView alloc] initWithFrame:self.dogTransContainer.bounds];
    [self.dogTransContainer addSubview:self.dogRotContainer];

    // 3. 构建五官
    [self buildEars];
    [self buildFace];

    [self layoutForCurrentStateAnimated:NO];

    // 手势
    UITapGestureRecognizer *tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapGestureOccurred:)];
    tapGesture.cancelsTouchesInView = NO;
    [self addGestureRecognizer:tapGesture];

    UIPanGestureRecognizer *panGesture = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(panGestureOccurred:)];
    panGesture.cancelsTouchesInView = NO;
    [self addGestureRecognizer:panGesture];
}

#pragma mark - 1:1 CSS 零件构建

- (void)buildEars {
    // 【核心修复：切短耳朵】
    CGFloat eW = 16.0/16.0 * _em;
    CGFloat eH = 15.0/16.0 * _em;

    // 左耳
    self.leftEar = [[UIView alloc] initWithFrame:CGRectMake(-2.0/16.0 * _em, -8.0/16.0 * _em, eW, eH)];
    [self setupEarStyle:self.leftEar];
    // 左耳旋转固定为 -40deg
    self.leftEar.transform = CGAffineTransformMakeRotation(-40 * M_PI / 180.0);
    [self.dogRotContainer addSubview:self.leftEar];

    // 右耳
    self.rightEar = [[UIView alloc] init];
    // 右耳动态锚点 (center bottom)
    self.rightEar.layer.anchorPoint = CGPointMake(0.5, 1.0);
    // 重置 Frame (注意 anchorPoint 更改后 frame 的起点)
    self.rightEar.frame = CGRectMake((2.5 * _em) - eW, -8.0/16.0 * _em, eW, eH);
    [self setupEarStyle:self.rightEar];
    [self.dogRotContainer addSubview:self.rightEar];
}

- (void)setupEarStyle:(UIView *)ear {
    ear.backgroundColor = ColorEar;
    CAShapeLayer *mask = [CAShapeLayer layer];
    mask.path = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(0, 0, ear.bounds.size.width, ear.bounds.size.height * 2)].CGPath;
    ear.layer.mask = mask;

    // 两侧白边
    UIView *leftWhite = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 4.0/16.0 * _em, ear.bounds.size.height)];
    leftWhite.backgroundColor = ColorFace;
    [ear addSubview:leftWhite];

    UIView *rightWhite = [[UIView alloc] initWithFrame:CGRectMake(ear.bounds.size.width - 4.0/16.0 * _em, 0, 4.0/16.0 * _em, ear.bounds.size.height)];
    rightWhite.backgroundColor = ColorFace;
    [ear addSubview:rightWhite];
}

- (void)buildFace {
    // 脸
    self.faceView = [[UIView alloc] initWithFrame:self.dogRotContainer.bounds];
    self.faceView.backgroundColor = ColorFace;
    self.faceView.layer.cornerRadius = 2.5 * _em / 2.0;
    self.faceView.layer.masksToBounds = YES;
    [self.dogRotContainer addSubview:self.faceView];

    // 眼斑
    CGFloat pCenterY = (14.0/16.0 - 4.0/16.0 + 4.0/16.0) * _em;
    CGFloat pCenterX = (8.0/16.0 + 22.0/16.0 + 4.0/16.0) * _em;
    CGFloat pRadius  = (4.0/16.0 + 12.0/16.0) * _em;
    UIView *patch = [[UIView alloc] initWithFrame:CGRectMake(pCenterX - pRadius, pCenterY - pRadius, pRadius * 2, pRadius * 2)];
    patch.backgroundColor = ColorPatch;
    patch.layer.cornerRadius = pRadius;
    [self.faceView addSubview:patch];

    // 眼睛
    CGFloat eyeSize = 8.0/16.0 * _em;
    UIView *leftEye = [[UIView alloc] initWithFrame:CGRectMake(8.0/16.0 * _em, 14.0/16.0 * _em, eyeSize, eyeSize)];
    leftEye.backgroundColor = ColorDark;
    leftEye.layer.cornerRadius = eyeSize / 2.0;
    [self.faceView addSubview:leftEye];

    UIView *rightEye = [[UIView alloc] initWithFrame:CGRectMake((8.0+16.0)/16.0 * _em, 14.0/16.0 * _em, eyeSize, eyeSize)];
    rightEye.backgroundColor = ColorDark;
    rightEye.layer.cornerRadius = eyeSize / 2.0;
    [self.faceView addSubview:rightEye];

    [self buildMouth];
}

- (void)buildMouth {
    // 嘴巴
    CGFloat mW = 14.0/16.0 * _em;
    CGFloat mH = 7.0/16.0 * _em;
    self.mouthContainer = [[UIView alloc] initWithFrame:CGRectMake((2.5 * _em - mW)/2.0, 2.5 * _em - 8.0/16.0 * _em - mH, mW, mH)];
    [self.faceView addSubview:self.mouthContainer];

    // 黑嘴
    CAShapeLayer *mouthShape = [CAShapeLayer layer];
    mouthShape.fillColor = ColorDark.CGColor;
    CGFloat rTop = 2.0/16.0 * _em;
    CGFloat rBot = 7.0/16.0 * _em;
    UIBezierPath *p = [UIBezierPath bezierPath];
    [p moveToPoint:CGPointMake(rTop, 0)];
    [p addLineToPoint:CGPointMake(mW - rTop, 0)];
    [p addArcWithCenter:CGPointMake(mW - rTop, rTop) radius:rTop startAngle:-M_PI_2 endAngle:0 clockwise:YES];
    [p addLineToPoint:CGPointMake(mW, mH - rBot)];
    [p addArcWithCenter:CGPointMake(mW - rBot, mH - rBot) radius:rBot startAngle:0 endAngle:M_PI_2 clockwise:YES];
    [p addLineToPoint:CGPointMake(rBot, mH)];
    [p addArcWithCenter:CGPointMake(rBot, mH - rBot) radius:rBot startAngle:M_PI_2 endAngle:M_PI clockwise:YES];
    [p addLineToPoint:CGPointMake(0, rTop)];
    [p addArcWithCenter:CGPointMake(rTop, rTop) radius:rTop startAngle:M_PI endAngle:-M_PI_2 clockwise:YES];
    [p closePath];
    mouthShape.path = p.CGPath;
    [self.mouthContainer.layer addSublayer:mouthShape];

    // 吐舌头
    CAShapeLayer *tongueShape = [CAShapeLayer layer];
    tongueShape.fillColor = ColorTongue.CGColor;
    CGFloat tW = 8.0/16.0 * _em;
    CGFloat tH = 8.0/16.0 * _em;
    UIBezierPath *tp = [UIBezierPath bezierPath];
    [tp moveToPoint:CGPointMake(0, 0)];
    [tp addLineToPoint:CGPointMake(tW, 0)];
    [tp addLineToPoint:CGPointMake(tW, tH/2)];
    [tp addArcWithCenter:CGPointMake(tW/2, tH/2) radius:tW/2 startAngle:0 endAngle:M_PI clockwise:YES];
    [tp closePath];
    tongueShape.path = tp.CGPath;
    tongueShape.transform = CATransform3DMakeTranslation(3.0/16.0 * _em, 5.0/16.0 * _em, 0);
    [self.mouthContainer.layer addSublayer:tongueShape];
}

#pragma mark - 交互动作引擎

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
        if (touchLocation.x > self.bounds.size.width / 2 && !self.isOn) { [self setOn:YES animated:YES]; }
        else if (touchLocation.x < self.bounds.size.width / 2 && self.isOn) { [self setOn:NO animated:YES]; }
    } else if (sender.state == UIGestureRecognizerStateEnded || sender.state == UIGestureRecognizerStateCancelled || sender.state == UIGestureRecognizerStateFailed) {
        self.dragging = NO;
        self.moved = NO;
        self.hovering = NO;
        [self animateHoverState];
    }
}

- (void)setOn:(BOOL)on { [self setOn:on animated:NO]; }

- (void)setOn:(BOOL)on animated:(BOOL)animated {
    if (_on == on) return;
    _on = on;
    if (self.changeAction && !_shouldSkipChangeAction && animated) { self.changeAction(on, YES); }

    [self layoutForCurrentStateAnimated:(animated && _shouldAnimateImportant)];
}

- (void)animateHoverState {
    [UIView animateWithDuration:0.3 animations:^{
        if (self.isHovering) {
            self.dogTransContainer.transform = CGAffineTransformMakeScale(0.95, 0.95);
        } else {
            [self layoutForCurrentStateAnimated:NO];
        }
    }];
}

- (void)layoutForCurrentStateAnimated:(BOOL)animated {
    // 1. 直线平移：由物理隔离的车厢层负责，杜绝漂移
    CGFloat targetX = self.isOn ? (4.05 * _em) : 0;

    if (animated) {
        // A. 车厢直线滑行 (0.6s)
        [UIView animateWithDuration:0.6 delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
            self.dogTransContainer.transform = CGAffineTransformMakeTranslation(targetX, 0);
        } completion:nil];

        // B. 狗头 360 度完美自转 (0.6s)
        CABasicAnimation *roll = [CABasicAnimation animationWithKeyPath:@"transform.rotation.z"];
        roll.fromValue = self.isOn ? @0 : @(2 * M_PI);
        roll.toValue = self.isOn ? @(2 * M_PI) : @0;
        roll.duration = 0.6;
        roll.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
        [self.dogRotContainer.layer addAnimation:roll forKey:@"rollAnim"];

        // 固化自转状态
        self.dogRotContainer.layer.transform = CATransform3DMakeRotation(self.isOn ? (2 * M_PI) : 0, 0, 0, 1);

        // C. 【核心修复：右耳回弹正向跟随】 (Delay: 0.6s)
        [UIView animateWithDuration:0.4 delay:(self.isOn ? 0.6 : 0) options:UIViewAnimationOptionCurveEaseInOut animations:^{
            [self applyRightEarTransform];
        } completion:nil];

        // D. 嘴巴弹出 (Delay: 0.7s)
        [UIView animateWithDuration:0.1 delay:(self.isOn ? 0.7 : 0) options:UIViewAnimationOptionCurveEaseInOut animations:^{
            self.mouthContainer.transform = self.isOn ? CGAffineTransformIdentity : CGAffineTransformMakeScale(0.001, 0.001);
        } completion:nil];

    } else {
        self.dogTransContainer.transform = CGAffineTransformMakeTranslation(targetX, 0);
        self.dogRotContainer.layer.transform = CATransform3DMakeRotation(self.isOn ? (2 * M_PI) : 0, 0, 0, 1);
        [self applyRightEarTransform];
        self.mouthContainer.transform = self.isOn ? CGAffineTransformIdentity : CGAffineTransformMakeScale(0.001, 0.001);
    }
}

- (void)applyRightEarTransform {
    // 【核心修复】：CSS 映射: scaleX(-1) 然后 rotate
    // 之前搞歪的原因是在同一个 transform 里叠加了两个 X/Y/Z 轴的属性。
    // 在 iOS 底层矩阵中，当 scaleX(-1) 时，旋转角速度的方向会发生反转。
    // 我们必须计算出这个反转后的物理矩阵。

    CATransform3D t = CATransform3DIdentity;

    // 获取 1:1 CSS 角度
    CGFloat angle = self.isOn ? (-35 * M_PI / 180.0) : (60 * M_PI / 180.0);

    // 先做水平镜像 scaleX(-1)
    t = CATransform3DScale(t, -1, 1, 1);

    // 【点睛之笔】：在镜像矩阵上应用旋转。此时旋转方向与 angle 完全正向对齐，不再“歪”。
    t = CATransform3DRotate(t, angle, 0, 0, 1);

    self.rightEar.layer.transform = t;
}

// ================== 兼容 Tweak ==================
- (CGFloat)knobMargin { return 0.2 * _em; }
- (void)blockChangeActionAnimated:(BOOL)animated { _shouldSkipChangeAction = YES; }
- (void)unblockChangeAction { _shouldSkipChangeAction = NO; }

@end
