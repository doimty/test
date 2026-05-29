//
//  TeethSwitch.m
//  TeethSwitch
//

#import "TeethSwitch.h"

// 颜色宏定义，精准提取自你的参考图
#define ColorMouthGrey   [UIColor colorWithRed:145/255.0 green:149/255.0 blue:152/255.0 alpha:1.0] // 闭合状态：高级灰
#define ColorMouthGreen  [UIColor colorWithRed:161/255.0 green:192/255.0 blue:132/255.0 alpha:1.0] // 开启状态：苹果绿
#define ColorToothWhite  [UIColor colorWithRed:255/255.0 green:255/255.0 blue:255/255.0 alpha:1.0] // 牙齿与滑块的纯白色
#define ColorGripLine    [UIColor colorWithRed:0/255.0 green:0/255.0 blue:0/255.0 alpha:0.3]       // 防滑纹颜色

@interface TeethSwitch ()

@property (nonatomic, strong) UIView *trackContainer;
@property (nonatomic, strong) UIView *mouthTrackView; // 口腔背景

// 核心：用于处理左斜/右斜形变的牙齿图层容器
@property (nonatomic, strong) UIView *teethContainer;

// 滑块组件
@property (nonatomic, strong) UIView *knobContainer;
@property (nonatomic, strong) UIView *knobView;

@property (nonatomic, assign) CGFloat em;

@property (nonatomic, assign, getter=isMoved) BOOL moved;
@property (nonatomic, assign, getter=isDragging) BOOL dragging;
@property (nonatomic, assign, getter=isOnBeforeDrag) BOOL onBeforeDrag;
@property (nonatomic, assign, getter=isHovering) BOOL hovering;

@end

@implementation TeethSwitch {
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

    // 比例系数：以高度为基准计算 1em
    _em = self.bounds.size.height / 2.0;
    CGFloat trackWidth = 3.5 * _em;
    CGFloat trackHeight = 2.0 * _em;

    // 居中容器
    self.trackContainer = [[UIView alloc] initWithFrame:CGRectMake((self.bounds.size.width - trackWidth)/2.0, (self.bounds.size.height - trackHeight)/2.0, trackWidth, trackHeight)];
    [self addSubview:self.trackContainer];

    // 1. 口腔背景 (Track) - 默认灰色
    self.mouthTrackView = [[UIView alloc] initWithFrame:self.trackContainer.bounds];
    self.mouthTrackView.backgroundColor = ColorMouthGrey;
    self.mouthTrackView.layer.cornerRadius = trackHeight / 2.0;
    // 【关键】裁切出圆角胶囊状，配合内部倾斜形变产生“跟随圆角”的视觉
    self.mouthTrackView.layer.masksToBounds = YES;

    // 阴影与边框
    self.trackContainer.layer.shadowColor = [UIColor blackColor].CGColor;
    self.trackContainer.layer.shadowOffset = CGSizeMake(0, 4);
    self.trackContainer.layer.shadowRadius = 8;
    self.trackContainer.layer.shadowOpacity = 0.15;
    self.mouthTrackView.layer.borderWidth = 1.0;
    self.mouthTrackView.layer.borderColor = [UIColor colorWithWhite:0 alpha:0.1].CGColor;
    [self.trackContainer addSubview:self.mouthTrackView];

    // 2. 核心动态层：牙齿容器 (将会进行 Skew 倾斜矩阵形变)
    self.teethContainer = [[UIView alloc] initWithFrame:self.mouthTrackView.bounds];
    [self.mouthTrackView addSubview:self.teethContainer];
    [self buildTeeth];

    // 3. 滑块容器 (用于平移)
    CGFloat knobDia = 1.4 * _em;
    self.knobContainer = [[UIView alloc] initWithFrame:CGRectMake(0.3 * _em, (trackHeight - knobDia)/2.0, knobDia, knobDia)];
    self.knobContainer.layer.shadowColor = [UIColor blackColor].CGColor;
    self.knobContainer.layer.shadowOffset = CGSizeMake(0, 2);
    self.knobContainer.layer.shadowRadius = 4;
    self.knobContainer.layer.shadowOpacity = 0.25;
    [self.trackContainer addSubview:self.knobContainer];

    // 滑块本体
    self.knobView = [[UIView alloc] initWithFrame:self.knobContainer.bounds];
    self.knobView.backgroundColor = ColorToothWhite;
    self.knobView.layer.cornerRadius = knobDia / 2.0;
    self.knobView.layer.masksToBounds = YES;
    [self.knobContainer addSubview:self.knobView];

    // 4. 添加垂直防滑纹 (|||)
    [self buildGripLines];

    [self layoutForCurrentStateAnimated:NO];

    // 添加手势
    UITapGestureRecognizer *tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapGestureOccurred:)];
    tapGesture.cancelsTouchesInView = NO;
    [self addGestureRecognizer:tapGesture];

    UIPanGestureRecognizer *panGesture = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(panGestureOccurred:)];
    panGesture.cancelsTouchesInView = YES;
    [self addGestureRecognizer:panGesture];
}

// 纯手工捏制牙齿 (4颗紧紧挨着)
- (void)buildTeeth {
    CGFloat w = self.mouthTrackView.bounds.size.width;
    CGFloat h = self.mouthTrackView.bounds.size.height;

    // 通过 X 坐标的微弱重叠，让 4 颗牙齿完美“挨着”没有缝隙
    // 上排 4 颗
    [self addToothWithFrame:CGRectMake(-w*0.02, -h*0.15, w*0.28, h*0.45) cornerRadius:h*0.2];
    [self addToothWithFrame:CGRectMake(w*0.24,  -h*0.1,  w*0.28, h*0.4)  cornerRadius:h*0.18];
    [self addToothWithFrame:CGRectMake(w*0.50,  -h*0.1,  w*0.28, h*0.4)  cornerRadius:h*0.18];
    [self addToothWithFrame:CGRectMake(w*0.76,  -h*0.15, w*0.28, h*0.45) cornerRadius:h*0.2];

    // 下排 4 颗
    [self addToothWithFrame:CGRectMake(-w*0.02, h*0.7,  w*0.28, h*0.45) cornerRadius:h*0.2];
    [self addToothWithFrame:CGRectMake(w*0.24,  h*0.7,  w*0.28, h*0.4)  cornerRadius:h*0.18];
    [self addToothWithFrame:CGRectMake(w*0.50,  h*0.7,  w*0.28, h*0.4)  cornerRadius:h*0.18];
    [self addToothWithFrame:CGRectMake(w*0.76,  h*0.7,  w*0.28, h*0.45) cornerRadius:h*0.2];
}

- (void)addToothWithFrame:(CGRect)frame cornerRadius:(CGFloat)radius {
    UIView *tooth = [[UIView alloc] initWithFrame:frame];
    tooth.backgroundColor = ColorToothWhite;
    tooth.layer.cornerRadius = radius;
    // 增加微弱的边缘描边，让相连的牙齿能看出独立轮廓
    tooth.layer.borderWidth = 1.0;
    tooth.layer.borderColor = [UIColor colorWithWhite:0.92 alpha:1.0].CGColor;
    [self.teethContainer addSubview:tooth];
}

// 绘制滑块上的垂直防滑纹 (|||)
- (void)buildGripLines {
    CGFloat knobDia = self.knobView.bounds.size.width;
    CGFloat lineW = knobDia * 0.06;
    CGFloat lineH = knobDia * 0.35;
    CGFloat spacing = knobDia * 0.15;

    CGFloat startX = (knobDia - (lineW * 3 + spacing * 2)) / 2.0;
    CGFloat startY = (knobDia - lineH) / 2.0;

    for (int i = 0; i < 3; i++) {
        UIView *line = [[UIView alloc] initWithFrame:CGRectMake(startX + i * (lineW + spacing), startY, lineW, lineH)];
        line.backgroundColor = ColorGripLine;
        line.layer.cornerRadius = lineW / 2.0;
        [self.knobView addSubview:line];
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
        if (@available(iOS 10.0, *)) {
            // 使用稍长一点的阻尼动画，凸显变形倾斜时的视觉过渡效果
            UICubicTimingParameters *timingParams = [[UICubicTimingParameters alloc] initWithControlPoint1:CGPointMake(0.25, 1.2) controlPoint2:CGPointMake(0.5, 1.0)];
            UIViewPropertyAnimator *animator = [[UIViewPropertyAnimator alloc] initWithDuration:0.55 timingParameters:timingParams];
            [animator addAnimations:^{
                [self layoutForCurrentStateAnimated:YES];
            }];
            [animator startAnimation];
        } else {
            [UIView animateWithDuration:0.55 delay:0.0 usingSpringWithDamping:0.75 initialSpringVelocity:0.5 options:UIViewAnimationOptionCurveEaseInOut animations:^{
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
            self.knobContainer.transform = CGAffineTransformMakeScale(0.9, 0.9);
        } else {
            self.knobContainer.transform = CGAffineTransformIdentity;
            [self layoutForCurrentStateAnimated:NO];
        }
    }];
}

- (void)layoutForCurrentStateAnimated:(BOOL)animated {
    // 1. 口腔背景颜色切换 (灰 -> 绿)
    self.mouthTrackView.backgroundColor = self.isOn ? ColorMouthGreen : ColorMouthGrey;

    // 2. 纯净滑块平移
    CGFloat targetX = self.isOn ? (1.8 * _em) : 0;
    self.knobContainer.transform = CGAffineTransformMakeTranslation(targetX, 0);

    // 3. 【核心点睛：牙齿倾斜 (Skew) 动画】
    // 关闭时 (NO): 牙齿向左斜 (-18度)
    // 开启时 (YES): 牙齿向右斜 (+18度)
    // 配合 masksToBounds 裁切，牙齿边缘倾斜时会完美贴合胶囊轨道的两端圆弧
    CGFloat skewAngle = self.isOn ? (18.0 * M_PI / 180.0) : (-18.0 * M_PI / 180.0);

    // CGAffineTransform: [a, b, c, d, tx, ty]
    // 倾斜 (SkewX) 由矩阵的参数 c 控制，值为 tan(angle)
    CGAffineTransform skewTransform = CGAffineTransformMake(1, 0, tan(skewAngle), 1, 0, 0);
    self.teethContainer.transform = skewTransform;
}

// ================== 兼容 Tweak ==================
- (CGFloat)knobMargin { return 0.3 * _em; }
- (void)blockChangeActionAnimated:(BOOL)animated { _shouldSkipChangeAction = YES; }
- (void)unblockChangeAction { _shouldSkipChangeAction = NO; }

@end
