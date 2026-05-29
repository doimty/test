//
//  DayNightSwitch.m
//  DayNightSwitch
//
//  (Liquid Glass + Rich Sun/Moon Visuals Edition)
//

#import "DayNightSwitch.h"


// ================= 【精致日月滑块 (Knob)】 =================
@interface Knob : UIView
@property(nonatomic, strong) UIView *sunView;
@property(nonatomic, strong) UIView *moonView;
@property(nonatomic, assign, getter=isOn) BOOL on;
@end

@implementation Knob

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    self.backgroundColor = [UIColor whiteColor]; // 基础底色
    self.layer.masksToBounds = YES;

    // 物理悬浮阴影 (加在外部，这里用 border 模拟一点玻璃质感)
    self.layer.borderWidth = 0.5;
    self.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.9].CGColor;

    CGFloat size = frame.size.width;

    // --- 1. 绘制太阳 (白天显示) ---
    self.sunView = [[UIView alloc] initWithFrame:self.bounds];
    self.sunView.backgroundColor = [UIColor colorWithRed:1.0 green:0.8 blue:0.1 alpha:1.0]; // 金黄色
    // 太阳内阴影/渐变感
    UIView *sunHighlight = [[UIView alloc] initWithFrame:CGRectMake(size*0.15, size*0.15, size*0.7, size*0.7)];
    sunHighlight.backgroundColor = [UIColor colorWithRed:1.0 green:0.9 blue:0.4 alpha:1.0];
    sunHighlight.layer.cornerRadius = size*0.35;
    [self.sunView addSubview:sunHighlight];
    [self addSubview:self.sunView];

    // --- 2. 绘制月亮 (夜间显示) ---
    self.moonView = [[UIView alloc] initWithFrame:self.bounds];
    self.moonView.backgroundColor = [UIColor colorWithWhite:0.9 alpha:1.0]; // 银灰色

    // 陨石坑
    NSArray *craters = @[
        [NSValue valueWithCGRect:CGRectMake(size * 0.2, size * 0.2, size * 0.25, size * 0.25)],
        [NSValue valueWithCGRect:CGRectMake(size * 0.55, size * 0.45, size * 0.3, size * 0.3)],
        [NSValue valueWithCGRect:CGRectMake(size * 0.3, size * 0.65, size * 0.2, size * 0.2)]
    ];
    for (NSValue *rectVal in craters) {
        UIView *crater = [[UIView alloc] initWithFrame:rectVal.CGRectValue];
        crater.backgroundColor = [UIColor colorWithWhite:0.8 alpha:1.0];
        crater.layer.cornerRadius = crater.frame.size.width / 2.0;
        // 陨石坑内阴影模拟
        crater.layer.borderWidth = 0.5;
        crater.layer.borderColor = [UIColor colorWithWhite:0.7 alpha:1.0].CGColor;
        [self.moonView addSubview:crater];
    }
    [self addSubview:self.moonView];

    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    self.layer.cornerRadius = self.bounds.size.height / 2.0;
    self.sunView.frame = self.bounds;
    self.sunView.layer.cornerRadius = self.bounds.size.height / 2.0;
    self.moonView.frame = self.bounds;
    self.moonView.layer.cornerRadius = self.bounds.size.height / 2.0;
}

- (void)setOn:(BOOL)on {
    _on = on;
}

@end


// ================= 【主开关控件】 =================
@interface DayNightSwitch ()
@property(nonatomic, strong) Knob *knob;
@property(nonatomic, strong) UIVisualEffectView *blurBackground;
@property(nonatomic, strong) UIView *colorTintView;

// 视觉元素图层
@property(nonatomic, strong) UIView *starsContainer;
@property(nonatomic, strong) UIView *cloudsContainer;

@property(nonatomic, assign, getter=isMoved) BOOL moved;
@property(nonatomic, assign, getter=isDragging) BOOL dragging;
@property(nonatomic, assign, getter=isOnBeforeDrag) BOOL onBeforeDrag;
@end

@implementation DayNightSwitch {
    BOOL _shouldSkipChangeAction;
    BOOL _shouldAnimateImportant;
}

- (CGFloat)knobMargin {
    return 3.0;
}

- (Knob *)setupKnob {
    CGFloat margin = [self knobMargin];
    CGFloat w = self.frame.size.height - margin * 2;
    Knob *v = [[Knob alloc] initWithFrame:CGRectMake(margin, margin, w, w)];

    // 给滑块本体加一个外阴影，立体感更强
    v.layer.shadowColor = [UIColor blackColor].CGColor;
    v.layer.shadowOffset = CGSizeMake(0, 2);
    v.layer.shadowOpacity = 0.2;
    v.layer.shadowRadius = 3.0;
    v.layer.masksToBounds = NO;

    self.knob = v;
    return v;
}

// 绘制星星
- (UIView *)setupStars {
    UIView *container = [[UIView alloc] initWithFrame:self.bounds];
    container.userInteractionEnabled = NO;
    CGFloat h = self.frame.size.height;
    CGFloat w = self.frame.size.width;
    CGFloat x = h * 0.08;

    NSArray *starRects = @[
        [NSValue valueWithCGRect:CGRectMake(w * 0.55, h * 0.20, x * 1.2, x * 1.2)],
        [NSValue valueWithCGRect:CGRectMake(w * 0.65, h * 0.40, x * 0.8, x * 0.8)],
        [NSValue valueWithCGRect:CGRectMake(w * 0.52, h * 0.65, x * 1.0, x * 1.0)],
        [NSValue valueWithCGRect:CGRectMake(w * 0.78, h * 0.25, x * 0.9, x * 0.9)],
        [NSValue valueWithCGRect:CGRectMake(w * 0.75, h * 0.65, x * 0.7, x * 0.7)],
        [NSValue valueWithCGRect:CGRectMake(w * 0.88, h * 0.45, x * 1.1, x * 1.1)],
        [NSValue valueWithCGRect:CGRectMake(w * 0.68, h * 0.75, x * 0.6, x * 0.6)]
    ];
    for (NSValue *rect in starRects) {
        UIView *star = [[UIView alloc] initWithFrame:rect.CGRectValue];
        star.backgroundColor = [UIColor whiteColor];
        star.layer.cornerRadius = star.frame.size.width / 2.0;
        star.layer.shadowColor = [UIColor whiteColor].CGColor;
        star.layer.shadowOpacity = 0.8;
        star.layer.shadowRadius = 2.0;
        star.layer.shadowOffset = CGSizeZero;

        // 【新增修复】：指定星光阴影路径，彻底根除渲染星星时的卡顿
        star.layer.shadowPath = [UIBezierPath bezierPathWithOvalInRect:star.bounds].CGPath;

        [container addSubview:star];
    }
    return container;
}

// 绘制云朵
- (UIView *)setupClouds {
    UIView *container = [[UIView alloc] initWithFrame:self.bounds];
    container.userInteractionEnabled = NO;
    CGFloat h = self.frame.size.height;
    CGFloat w = self.frame.size.width;

    // 用几个圆角矩形拼接成云朵的形状
    UIView *cloud1 = [[UIView alloc] initWithFrame:CGRectMake(w * 0.15, h * 0.4, w * 0.3, h * 0.35)];
    cloud1.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.8];
    cloud1.layer.cornerRadius = cloud1.frame.size.height / 2.0;
    [container addSubview:cloud1];

    UIView *cloud2 = [[UIView alloc] initWithFrame:CGRectMake(w * 0.25, h * 0.25, w * 0.25, h * 0.35)];
    cloud2.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.8];
    cloud2.layer.cornerRadius = cloud2.frame.size.height / 2.0;
    [container addSubview:cloud2];

    return container;
}

- (instancetype)initWithCenter:(CGPoint)center {
    CGFloat height = 30;
    CGFloat width = height * 1.75;
    self = [super initWithFrame:CGRectMake(center.x - width / 2, center.y - height / 2, width, height)];
    [self commonInit];
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)aDecoder {
    self = [super initWithCoder:aDecoder];
    [self commonInit];
    return self;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    [self commonInit];
    return self;
}

- (void)commonInit {
    _shouldAnimateImportant = YES;
    self.moved = NO;
    self.dragging = NO;
    self.backgroundColor = [UIColor clearColor];

    // --- 1. 毛玻璃底座层 ---
    UIBlurEffect *blurEffect;
    if (@available(iOS 13.0, *)) {
        blurEffect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterialLight];
    } else {
        blurEffect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleLight];
    }
    self.blurBackground = [[UIVisualEffectView alloc] initWithEffect:blurEffect];
    self.blurBackground.userInteractionEnabled = NO;
    self.blurBackground.layer.masksToBounds = YES;
    self.blurBackground.layer.borderWidth = 1.0;
    self.blurBackground.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.3].CGColor;
    [self addSubview:self.blurBackground];

    // --- 2. 颜色浸染层 ---
    self.colorTintView = [[UIView alloc] init];
    self.colorTintView.userInteractionEnabled = NO;
    self.colorTintView.layer.masksToBounds = YES;  // 这个层会严格裁剪多余内容
    [self addSubview:self.colorTintView];

    // --- 3. 视觉元素层 (星星和云朵) ---
    // 修改点 1：将元素添加到 colorTintView 内部，这样升降时绝不会越界跑到隔壁开关
    self.starsContainer = [self setupStars];
    [self.colorTintView addSubview:self.starsContainer];

    self.cloudsContainer = [self setupClouds];
    [self.colorTintView addSubview:self.cloudsContainer];

    // --- 4. 注入滑块 ---
    [self addSubview:[self setupKnob]];

    // --- 5. 绑定手势 ---
    UITapGestureRecognizer *tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapGestureOccurred:)];
    tapGesture.cancelsTouchesInView = NO;
    [self addGestureRecognizer:tapGesture];

    UIPanGestureRecognizer *panGesture = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(panGestureOccurred:)];
    panGesture.cancelsTouchesInView = YES;
    [self addGestureRecognizer:panGesture];

    [self _setOn:NO animated:NO];
}

// 绝对布局，防止错位
- (void)layoutSubviews {
    [super layoutSubviews];

    CGFloat radius = self.bounds.size.height / 2.0;
    self.blurBackground.frame = self.bounds;
    self.blurBackground.layer.cornerRadius = radius;
    self.colorTintView.frame = self.bounds;
    self.colorTintView.layer.cornerRadius = radius;

    if (@available(iOS 13.0, *)) {
        self.blurBackground.layer.cornerCurve = kCACornerCurveContinuous;
        self.colorTintView.layer.cornerCurve = kCACornerCurveContinuous;
    }

    if (!self.isDragging) {
        CGFloat margin = [self knobMargin];
        CGFloat knobH = self.bounds.size.height - margin * 2;
        CGFloat targetX = self.isOn ? (self.bounds.size.width - margin - knobH/2.0) : (margin + knobH/2.0);
        self.knob.bounds = CGRectMake(0, 0, knobH, knobH);
        self.knob.center = CGPointMake(targetX, self.bounds.size.height / 2.0);
    }

    // 【新增修复】：为主滑块(Knob)加上阴影路径，消除开关位移时的极大性能消耗
    self.knob.layer.shadowPath = [UIBezierPath bezierPathWithOvalInRect:self.knob.bounds].CGPath;
}

// ================= 【交互与动画】 =================

- (void)panGestureOccurred:(UIPanGestureRecognizer *)sender {
    CGPoint touchLocation = [sender locationInView:self];

    if (sender.state == UIGestureRecognizerStateBegan) {
        self.onBeforeDrag = self.isOn;
        self.dragging = YES;
        // 按下瞬间：滑块液态收缩
        [UIView animateWithDuration:0.2 animations:^{
            self.knob.transform = CGAffineTransformMakeScale(0.8, 0.8);
        }];
    } else if (sender.state == UIGestureRecognizerStateChanged) {
        self.moved = YES;
        if (touchLocation.x > self.bounds.size.width / 2 && !self.isOn) {
            self.on = YES;
        } else if (touchLocation.x < self.bounds.size.width / 2 && self.isOn) {
            self.on = NO;
        }
    } else if (sender.state == UIGestureRecognizerStateEnded || sender.state == UIGestureRecognizerStateCancelled ||
               sender.state == UIGestureRecognizerStateFailed) {
        self.dragging = NO;
        self.moved = NO;

        // 松手瞬间：弹性恢复
        [UIView animateWithDuration:0.4 delay:0 usingSpringWithDamping:0.6 initialSpringVelocity:0.8 options:UIViewAnimationOptionCurveEaseOut animations:^{
            self.knob.transform = CGAffineTransformIdentity;
        } completion:nil];

        if (self.isOn != self.isOnBeforeDrag && self.changeAction) {
            self.changeAction(self.isOn, YES);
        }
    }
}

- (void)tapGestureOccurred:(UITapGestureRecognizer *)sender {
    if (self.isDragging) return;
    self.dragging = YES;
    self.on = !self.isOn;
    self.dragging = NO;
}

- (void)setOn:(BOOL)on {
    if (_on == on) return;
    _on = on;

    // 【新增修复】：当 self.window 为 nil（比如刚初始化或在列表复用刚创建时），直接取消动画，防止刚打开页面时瞎弹
    BOOL shouldAnimate = (self.window != nil);
    [self _setOn:on animated:shouldAnimate];
}

- (void)setOn:(BOOL)on animated:(BOOL)animated {
    if (_on == on) return;
    _on = on;
    [self _setOn:on animated:animated];
}

// 核心状态切换动画
- (void)_setOn:(BOOL)on animated:(BOOL)animated {
    if (self.changeAction && !_shouldSkipChangeAction && animated) {
        self.changeAction(on, !self.isMoved);
    }

    self.knob.on = on;

    CGFloat margin = [self knobMargin];
    CGFloat knobRadius = self.knob.bounds.size.width / 2.0;
    CGFloat centerY = self.bounds.size.height / 2.0;
    CGFloat targetX = on ? (self.bounds.size.width - margin - knobRadius) : (margin + knobRadius);

    BOOL doAnimate = animated && _shouldAnimateImportant;
    CGFloat duration = doAnimate ? 0.45 : 0.0;

    if (doAnimate) {
        if (!self.isDragging) {
            // 点击时的初始挤压形变
            self.knob.transform = CGAffineTransformMakeScale(0.75, 0.75);
        }

        [UIView animateWithDuration:duration
                              delay:0
             usingSpringWithDamping:0.65
              initialSpringVelocity:0.8
                            options:UIViewAnimationOptionCurveEaseInOut | UIViewAnimationOptionAllowUserInteraction
                         animations:^{

            self.knob.center = CGPointMake(targetX, centerY);
            self.knob.transform = CGAffineTransformIdentity;

            if (on) {
                // 打开：白天模式
                self.colorTintView.backgroundColor = [UIColor colorWithRed:0.3 green:0.7 blue:1.0 alpha:0.7]; // 晴空蓝
                // 内部滑块变为太阳
                self.knob.sunView.alpha = 1.0;
                self.knob.moonView.alpha = 0.0;
                // 显示云朵，隐藏星星
                self.cloudsContainer.alpha = 1.0;
                self.cloudsContainer.transform = CGAffineTransformIdentity;
                self.starsContainer.alpha = 0.0;
                self.starsContainer.transform = CGAffineTransformMakeTranslation(10, 20); // 星星坠落消失
            } else {
                // 关闭：夜间模式
                self.colorTintView.backgroundColor = [UIColor colorWithRed:0.1 green:0.1 blue:0.25 alpha:0.8]; // 深夜蓝
                // 内部滑块变为月亮
                self.knob.sunView.alpha = 0.0;
                self.knob.moonView.alpha = 1.0;
                // 显示星星，隐藏云朵
                self.starsContainer.alpha = 1.0;
                self.starsContainer.transform = CGAffineTransformIdentity;
                self.cloudsContainer.alpha = 0.0;
                self.cloudsContainer.transform = CGAffineTransformMakeTranslation(-10, 20); // 云朵飘走消失
            }

        } completion:nil];

    } else {
        self.knob.center = CGPointMake(targetX, centerY);
        self.knob.transform = CGAffineTransformIdentity;

        self.colorTintView.backgroundColor = on ? [UIColor colorWithRed:0.3 green:0.7 blue:1.0 alpha:0.7] : [UIColor colorWithRed:0.1 green:0.1 blue:0.25 alpha:0.8];
        self.knob.sunView.alpha = on ? 1.0 : 0.0;
        self.knob.moonView.alpha = on ? 0.0 : 1.0;
        self.cloudsContainer.alpha = on ? 1.0 : 0.0;
        self.starsContainer.alpha = on ? 0.0 : 1.0;

        // 修改点 2：修复列表上下滑动复用时的状态错乱问题，强制复位
        self.cloudsContainer.transform = on ? CGAffineTransformIdentity : CGAffineTransformMakeTranslation(-10, 20);
        self.starsContainer.transform = on ? CGAffineTransformMakeTranslation(10, 20) : CGAffineTransformIdentity;
    }
}

- (void)blockChangeActionAnimated:(BOOL)animated {
    _shouldSkipChangeAction = YES;
}

- (void)unblockChangeAction {
    _shouldSkipChangeAction = NO;
}

@end
