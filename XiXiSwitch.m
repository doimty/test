//
//  XiXiSwitch.m
//  XiXiSwitch (终极拟态立体描边版：复刻 CSS 凹凸光影)
//

#import "XiXiSwitch.h"

// 严格提取自 CSS
#define ColorTrackOff    [UIColor colorWithRed:200/255.0 green:204/255.0 blue:210/255.0 alpha:1.0] // hsl(223, 10%, 80%)
#define ColorTrackOn     [UIColor colorWithRed:10/255.0 green:194/255.0 blue:19/255.0 alpha:1.0]   // #0ac213
#define ColorEmojiYellow [UIColor colorWithRed:242/255.0 green:196/255.0 blue:13/255.0 alpha:1.0]  // #f2c40d
#define ColorDark        [UIColor colorWithRed:23/255.0 green:24/255.0 blue:26/255.0 alpha:1.0]    // hsl(223, 10%, 10%)
#define ColorMouthRed    [UIColor colorWithRed:242/255.0 green:24/255.0 blue:13/255.0 alpha:1.0]   // #f2180d

@interface XiXiSwitch ()

@property (nonatomic, strong) UIView *trackContainer;
@property (nonatomic, strong) UIView *trackView;

// 滑块总容器 (负责平移)
@property (nonatomic, strong) UIView *knobContainer;
// 3D 旋转层 (负责滚动五官)
@property (nonatomic, strong) CATransformLayer *spinLayer;

@property (nonatomic, assign) CGFloat em;
@property (nonatomic, assign, getter=isMoved) BOOL moved;
@property (nonatomic, assign, getter=isDragging) BOOL dragging;
@property (nonatomic, assign, getter=isOnBeforeDrag) BOOL onBeforeDrag;
@property (nonatomic, assign, getter=isHovering) BOOL hovering;

@end

@implementation XiXiSwitch {
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

    _em = self.bounds.size.height / 2.0;
    CGFloat trackWidth = 3.5 * _em;
    CGFloat trackHeight = 2.0 * _em;

    self.trackContainer = [[UIView alloc] initWithFrame:CGRectMake((self.bounds.size.width - trackWidth)/2.0, (self.bounds.size.height - trackHeight)/2.0, trackWidth, trackHeight)];
    [self addSubview:self.trackContainer];

    // ==========================================
    // 1. 轨道层 (带外部微弱阴影)
    // ==========================================
    self.trackView = [[UIView alloc] initWithFrame:self.trackContainer.bounds];
    self.trackView.backgroundColor = ColorTrackOff;
    self.trackView.layer.cornerRadius = trackHeight / 2.0;
    self.trackView.layer.masksToBounds = YES; // 必须开启以裁切内描边

    // 轨道的外部环境投影
    self.trackContainer.layer.shadowColor = [UIColor blackColor].CGColor;
    self.trackContainer.layer.shadowOffset = CGSizeMake(0, 1.5);
    self.trackContainer.layer.shadowRadius = 2;
    self.trackContainer.layer.shadowOpacity = 0.15;

    // 【终极细节：3D 轨道内凹描边 (复刻 CSS box-shadow inset)】
    // 左上角深色阴影，右下角白色反光，形成“雕刻凹槽”的立体感
    CAGradientLayer *track3DStroke = [CAGradientLayer layer];
    track3DStroke.frame = self.trackView.bounds;
    track3DStroke.colors = @[
        (__bridge id)[UIColor colorWithWhite:0.0 alpha:0.35].CGColor, // 左上暗部 (凹陷的背光面)
        (__bridge id)[UIColor colorWithWhite:1.0 alpha:0.9].CGColor   // 右下亮部 (凹陷的迎光面)
    ];
    track3DStroke.startPoint = CGPointMake(0, 0);
    track3DStroke.endPoint = CGPointMake(1, 1);

    // 使用形状遮罩，将渐变裁切成一条完美的贴边线
    CAShapeLayer *strokeMask = [CAShapeLayer layer];
    strokeMask.path = [UIBezierPath bezierPathWithRoundedRect:self.trackView.bounds cornerRadius:trackHeight/2.0].CGPath;
    strokeMask.fillColor = [UIColor clearColor].CGColor;
    strokeMask.strokeColor = [UIColor blackColor].CGColor;
    strokeMask.lineWidth = 4.0; // 一半在内一半在外，外部被 trackView.masksToBounds 裁掉
    track3DStroke.mask = strokeMask;

    [self.trackView.layer addSublayer:track3DStroke];
    [self.trackContainer addSubview:self.trackView];

    // ==========================================
    // 2. 独立滑块容器 (带外侧悬浮阴影)
    // ==========================================
    CGFloat knobDia = 1.4 * _em;
    CGFloat R = knobDia / 2.0;
    self.knobContainer = [[UIView alloc] initWithFrame:CGRectMake(0.3 * _em, (trackHeight - knobDia)/2.0, knobDia, knobDia)];
    self.knobContainer.layer.shadowColor = [UIColor blackColor].CGColor;
    self.knobContainer.layer.shadowOffset = CGSizeMake(0.25 * _em, 0.25 * _em);
    self.knobContainer.layer.shadowRadius = 2;
    self.knobContainer.layer.shadowOpacity = 0.3;
    [self.trackContainer addSubview:self.knobContainer];

    // 透视景深
    CATransform3D perspective = CATransform3DIdentity;
    perspective.m34 = -1.0 / 300.0;
    self.knobContainer.layer.sublayerTransform = perspective;

    // ==========================================
    // 3. 3D 黄球基底
    // ==========================================
    CAGradientLayer *sphereBase = [CAGradientLayer layer];
    sphereBase.type = kCAGradientLayerRadial;
    sphereBase.frame = self.knobContainer.bounds;
    sphereBase.cornerRadius = R;
    sphereBase.masksToBounds = YES;
    sphereBase.startPoint = CGPointMake(0.25, 0.25);
    sphereBase.endPoint = CGPointMake(1.0, 1.0);
    sphereBase.colors = @[
        (__bridge id)[UIColor colorWithRed:249/255.0 green:226/255.0 blue:134/255.0 alpha:1.0].CGColor,
        (__bridge id)[UIColor colorWithRed:242/255.0 green:196/255.0 blue:13/255.0 alpha:1.0].CGColor,
        (__bridge id)[UIColor colorWithRed:194/255.0 green:157/255.0 blue:10/255.0 alpha:1.0].CGColor
    ];

    // 【终极细节：3D 表情凸起描边 (复刻 CSS emoji inset shadow)】
    // 左上角白色高光边，右下角深棕色暗边，让表情包像一枚立体硬币
    CAGradientLayer *emoji3DStroke = [CAGradientLayer layer];
    emoji3DStroke.frame = self.knobContainer.bounds;
    emoji3DStroke.colors = @[
        (__bridge id)[UIColor colorWithRed:255/255.0 green:245/255.0 blue:200/255.0 alpha:0.9].CGColor, // 左上亮边
        (__bridge id)[UIColor colorWithRed:180/255.0 green:130/255.0 blue:10/255.0 alpha:0.8].CGColor  // 右下暗边
    ];
    emoji3DStroke.startPoint = CGPointMake(0, 0);
    emoji3DStroke.endPoint = CGPointMake(1, 1);

    CAShapeLayer *emojiMask = [CAShapeLayer layer];
    emojiMask.path = [UIBezierPath bezierPathWithOvalInRect:self.knobContainer.bounds].CGPath;
    emojiMask.fillColor = [UIColor clearColor].CGColor;
    emojiMask.strokeColor = [UIColor blackColor].CGColor;
    emojiMask.lineWidth = 3.0; // 内描边宽度
    emoji3DStroke.mask = emojiMask;

    [sphereBase addSublayer:emoji3DStroke];
    [self.knobContainer.layer addSublayer:sphereBase];

    // ==========================================
    // 4. 旋转层
    // ==========================================
    self.spinLayer = [CATransformLayer layer];
    self.spinLayer.frame = self.knobContainer.bounds;
    [self.knobContainer.layer addSublayer:self.spinLayer];

    // 捏脸
    [self buildSadFaceFeaturesWithRadius:R];
    [self buildHappyFaceFeaturesWithRadius:R];

    [self layoutForCurrentStateAnimated:NO];

    // 手势
    UITapGestureRecognizer *tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapGestureOccurred:)];
    tapGesture.cancelsTouchesInView = NO;
    [self addGestureRecognizer:tapGesture];

    UIPanGestureRecognizer *panGesture = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(panGestureOccurred:)];
    panGesture.cancelsTouchesInView = YES;
    [self addGestureRecognizer:panGesture];
}

#pragma mark - 1:1 CSS 矩阵算法映射

- (void)buildSadFaceFeaturesWithRadius:(CGFloat)R {
    CGFloat dia = R * 2.0;
    CGFloat eyeSize = dia * 0.1875;

    // 1. 不嘻嘻左眼
    CALayer *leftEye = [self createBaseFeatureLayer:eyeSize];
    leftEye.backgroundColor = ColorDark.CGColor;
    leftEye.cornerRadius = eyeSize / 2.0;
    leftEye.transform = [self transformForFace:0 translateY:0 rotateY:-22.5 rotateX:0 translateZ:R rotateZ:0];
    [self.spinLayer addSublayer:leftEye];

    // 2. 不嘻嘻右眼
    CALayer *rightEye = [self createBaseFeatureLayer:eyeSize];
    rightEye.backgroundColor = ColorDark.CGColor;
    rightEye.cornerRadius = eyeSize / 2.0;
    rightEye.transform = [self transformForFace:0 translateY:0 rotateY:22.5 rotateX:0 translateZ:R rotateZ:0];
    [self.spinLayer addSublayer:rightEye];

    // 3. 不嘻嘻短嘴巴
    CGFloat mouthSize = dia * 0.5;
    CAShapeLayer *mouth = (CAShapeLayer *)[self createBaseFeatureLayer:mouthSize];
    UIBezierPath *mPath = [UIBezierPath bezierPathWithArcCenter:CGPointMake(mouthSize/2, mouthSize/2) radius:mouthSize/2 startAngle:M_PI + 0.7 endAngle:M_PI*2 - 0.7 clockwise:YES];
    mouth.path = mPath.CGPath;
    mouth.strokeColor = ColorDark.CGColor;
    mouth.fillColor = nil;
    mouth.lineWidth = dia * 0.05;
    mouth.lineCap = kCALineCapRound;

    mouth.transform = [self transformForFace:0 translateY:dia * 0.25 rotateY:0 rotateX:-20 translateZ:R rotateZ:0];
    [self.spinLayer addSublayer:mouth];
}

- (void)buildHappyFaceFeaturesWithRadius:(CGFloat)R {
    CGFloat dia = R * 2.0;
    CGFloat baseFaceY = M_PI;
    CGFloat eyeSize = dia * 0.25;

    // 1. 嘻嘻左眼
    CAShapeLayer *leftEye = (CAShapeLayer *)[self createBaseFeatureLayer:eyeSize];
    UIBezierPath *ePath = [UIBezierPath bezierPathWithArcCenter:CGPointMake(eyeSize/2, eyeSize/2) radius:eyeSize/2 startAngle:M_PI+0.1 endAngle:M_PI*1.5-0.1 clockwise:YES];
    leftEye.path = ePath.CGPath;
    leftEye.strokeColor = ColorDark.CGColor;
    leftEye.fillColor = nil;
    leftEye.lineWidth = dia * 0.05;
    leftEye.lineCap = kCALineCapRound;
    leftEye.transform = [self transformForFace:baseFaceY translateY:0 rotateY:-22.5 rotateX:0 translateZ:R rotateZ:45];
    [self.spinLayer addSublayer:leftEye];

    // 2. 嘻嘻右眼
    CAShapeLayer *rightEye = (CAShapeLayer *)[self createBaseFeatureLayer:eyeSize];
    rightEye.path = ePath.CGPath;
    rightEye.strokeColor = ColorDark.CGColor;
    rightEye.fillColor = nil;
    rightEye.lineWidth = dia * 0.05;
    rightEye.lineCap = kCALineCapRound;
    rightEye.transform = [self transformForFace:baseFaceY translateY:0 rotateY:22.5 rotateX:0 translateZ:R rotateZ:45];
    [self.spinLayer addSublayer:rightEye];

    // 3. 嘻嘻嘴巴 (黑色深口腔 + 红舌头)
    CGFloat mouthSize = dia * 0.5;
    CAShapeLayer *mouth = (CAShapeLayer *)[self createBaseFeatureLayer:mouthSize];
    UIBezierPath *mPath = [UIBezierPath bezierPathWithArcCenter:CGPointMake(mouthSize/2, mouthSize/2) radius:mouthSize/2 startAngle:0 endAngle:M_PI clockwise:YES];
    [mPath closePath];
    mouth.path = mPath.CGPath;
    mouth.fillColor = ColorDark.CGColor;
    mouth.strokeColor = ColorDark.CGColor;
    mouth.lineWidth = dia * 0.02;
    mouth.lineJoin = kCALineJoinRound;

    CAShapeLayer *tongue = [CAShapeLayer layer];
    CGFloat tRadius = mouthSize * 0.35;
    CGFloat tOffset = (mouthSize / 2.0) - tRadius;
    UIBezierPath *tPath = [UIBezierPath bezierPathWithArcCenter:CGPointMake(mouthSize/2, mouthSize/2 + tOffset) radius:tRadius startAngle:0 endAngle:M_PI clockwise:YES];
    [tPath closePath];
    tongue.path = tPath.CGPath;
    tongue.fillColor = ColorMouthRed.CGColor;
    [mouth addSublayer:tongue];

    mouth.transform = [self transformForFace:baseFaceY translateY:0 rotateY:0 rotateX:-15 translateZ:R rotateZ:0];
    [self.spinLayer addSublayer:mouth];
}

// 工厂：保证转到背面时自动剔除隐藏
- (CALayer *)createBaseFeatureLayer:(CGFloat)size {
    CAShapeLayer *layer = [CAShapeLayer layer];
    layer.bounds = CGRectMake(0, 0, size, size);
    layer.position = CGPointMake(self.spinLayer.bounds.size.width / 2.0, self.spinLayer.bounds.size.height / 2.0);
    layer.doubleSided = NO;
    return layer;
}

// 核心矩阵：加入 translateY 支持
- (CATransform3D)transformForFace:(CGFloat)baseY translateY:(CGFloat)tY rotateY:(CGFloat)y rotateX:(CGFloat)x translateZ:(CGFloat)z rotateZ:(CGFloat)zRot {
    CATransform3D t = CATransform3DIdentity;
    t = CATransform3DRotate(t, baseY, 0, 1, 0);
    t = CATransform3DTranslate(t, 0, tY, 0);
    t = CATransform3DRotate(t, y * M_PI / 180.0, 0, 1, 0);
    t = CATransform3DRotate(t, x * M_PI / 180.0, 1, 0, 0);
    t = CATransform3DTranslate(t, 0, 0, z);
    t = CATransform3DRotate(t, zRot * M_PI / 180.0, 0, 0, 1);
    return t;
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

    if (animated && _shouldAnimateImportant) {
        [UIView animateWithDuration:0.5 delay:0.0 usingSpringWithDamping:0.8 initialSpringVelocity:0.2 options:UIViewAnimationOptionCurveEaseInOut animations:^{
            [self layoutForCurrentStateAnimated:YES];
        } completion:nil];
    } else {
        [self layoutForCurrentStateAnimated:NO];
    }
}

- (void)animateHoverState {
    [UIView animateWithDuration:0.3 animations:^{
        if (self.isHovering) {
            self.knobContainer.transform = CGAffineTransformMakeScale(0.95, 0.95);
        } else {
            [self layoutForCurrentStateAnimated:NO];
        }
    }];
}

- (void)layoutForCurrentStateAnimated:(BOOL)animated {
    self.trackView.backgroundColor = self.isOn ? ColorTrackOn : ColorTrackOff;

    CGFloat targetX = self.isOn ? (self.trackContainer.bounds.size.width - self.knobContainer.bounds.size.width - 0.6 * _em) : 0;
    self.knobContainer.transform = CGAffineTransformMakeTranslation(targetX, 0);

    CGFloat angle = self.isOn ? M_PI : 0;
    self.spinLayer.transform = CATransform3DMakeRotation(angle, 0, 1, 0);
}

- (CGFloat)knobMargin { return 0.3 * _em; }
- (void)blockChangeActionAnimated:(BOOL)animated { _shouldSkipChangeAction = YES; }
- (void)unblockChangeAction { _shouldSkipChangeAction = NO; }

@end
