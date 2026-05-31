//
//  StripedSwitch.m
//  StripedSwitch (浅灰关闭 + 浅豆绿 #C0D6C4 开启版)
//

#import "StripedSwitch.h"

// ================= 【主开关控件】 =================
@interface StripedSwitch ()
@property (nonatomic, strong) UIView *trackView;         // 轨道底座
@property (nonatomic, strong) UIView *knobView;          // 亮银金属滑块
@property (nonatomic, strong) CAGradientLayer *knobGrad; // 滑块金属渐变层
@property (nonatomic, strong) CAGradientLayer *innerIndicator; // 能量核心

// 独立的三根线 (穿梭波浪)
@property (nonatomic, strong) UIView *line1;
@property (nonatomic, strong) UIView *line2;
@property (nonatomic, strong) UIView *line3;

@property (nonatomic, assign, getter=isMoved) BOOL moved;
@property (nonatomic, assign, getter=isDragging) BOOL dragging;
@property (nonatomic, assign, getter=isOnBeforeDrag) BOOL onBeforeDrag;
@end

@implementation StripedSwitch {
    BOOL _shouldSkipChangeAction;
    BOOL _shouldAnimateImportant;
}

- (CGFloat)knobMargin {
    return 3.0;
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

    // --- 1. 底座 ---
    self.trackView = [[UIView alloc] initWithFrame:self.bounds];
    self.trackView.layer.masksToBounds = YES;
    if (@available(iOS 13.0, *)) {
        self.trackView.layer.cornerCurve = kCACornerCurveContinuous;
    }
    self.trackView.layer.borderWidth = 0.5;
    self.trackView.layer.borderColor = [UIColor colorWithWhite:0.0 alpha:0.1].CGColor;
    [self addSubview:self.trackView];

    // --- 2. 极光三道杠 ---
    CGFloat h = 2.5;
    self.line1 = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 10, h)];
    self.line2 = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 16, h)];
    self.line3 = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 12, h)];

    for (UIView *line in @[self.line1, self.line2, self.line3]) {
        line.layer.cornerRadius = h / 2.0;
        line.layer.shadowOffset = CGSizeZero;
        line.layer.shadowRadius = 4.0;
        [self addSubview:line];
    }

    // --- 3. 亮银金属滑块 ---
    CGFloat margin = [self knobMargin];
    CGFloat knobH = self.bounds.size.height - margin * 2;
    self.knobView = [[UIView alloc] initWithFrame:CGRectMake(margin, margin, knobH, knobH)];

    // 金属渐变 (亮银白)
    self.knobGrad = [CAGradientLayer layer];
    self.knobGrad.frame = self.knobView.bounds;
    self.knobGrad.cornerRadius = knobH / 2.0;
    self.knobGrad.startPoint = CGPointMake(0, 0);
    self.knobGrad.endPoint = CGPointMake(1, 1);
    [self.knobView.layer addSublayer:self.knobGrad];

    // 高光边缘
    self.knobView.layer.borderWidth = 0.5;
    self.knobView.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.9].CGColor;

    // 内部能量核心 (呼应浅豆绿背景，使用极浅的同色系渐变到白)
    CGFloat innerH = knobH * 0.35;
    self.innerIndicator = [CAGradientLayer layer];
    self.innerIndicator.frame = CGRectMake((knobH - innerH)/2.0, (knobH - innerH)/2.0, innerH, innerH);
    self.innerIndicator.cornerRadius = innerH / 2.0;
    self.innerIndicator.startPoint = CGPointMake(0, 0);
    self.innerIndicator.endPoint = CGPointMake(1, 1);
    self.innerIndicator.colors = @[
        (id)[UIColor colorWithRed:220.0/255.0 green:235.0/255.0 blue:224.0/255.0 alpha:1.0].CGColor,
        (id)[UIColor colorWithRed:192.0/255.0 green:214.0/255.0 blue:196.0/255.0 alpha:1.0].CGColor, // #C0D6C4
        (id)[UIColor whiteColor].CGColor
    ];
    self.innerIndicator.opacity = 0.0;
    [self.knobView.layer addSublayer:self.innerIndicator];

    // 悬浮阴影
    self.knobView.layer.shadowColor = [UIColor blackColor].CGColor;
    self.knobView.layer.shadowOffset = CGSizeMake(0, 3);
    self.knobView.layer.shadowOpacity = 0.0;
    self.knobView.layer.shadowRadius = 5.0;
    self.knobView.layer.masksToBounds = NO;

    [self addSubview:self.knobView];

    // --- 4. 手势绑定 ---
    UITapGestureRecognizer *tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapGestureOccurred:)];
    tapGesture.cancelsTouchesInView = NO;
    [self addGestureRecognizer:tapGesture];

    UIPanGestureRecognizer *panGesture = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(panGestureOccurred:)];
    panGesture.cancelsTouchesInView = YES;
    [self addGestureRecognizer:panGesture];

    [self _setOn:NO animated:NO];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat radius = self.bounds.size.height / 2.0;
    self.trackView.frame = self.bounds;
    self.trackView.layer.cornerRadius = radius;

    CGFloat margin = [self knobMargin];
    CGFloat knobH = self.bounds.size.height - margin * 2;
    self.knobView.layer.cornerRadius = knobH / 2.0;
    self.knobGrad.frame = self.knobView.bounds;
    self.knobGrad.cornerRadius = knobH / 2.0;
    self.knobView.layer.shadowPath = [UIBezierPath bezierPathWithOvalInRect:self.knobView.bounds].CGPath;

    if (!self.isDragging) {
        CGFloat targetX = self.isOn ? (self.bounds.size.width - margin - knobH/2.0) : (margin + knobH/2.0);
        self.knobView.bounds = CGRectMake(0, 0, knobH, knobH);
        self.knobView.center = CGPointMake(targetX, self.bounds.size.height / 2.0);

        CGFloat linesTargetX = self.isOn ? (targetX - knobH/2.0 - 10) : (targetX + knobH/2.0 + 10);
        CGFloat centerY = self.bounds.size.height / 2.0;
        self.line1.center = CGPointMake(linesTargetX, centerY - 6.0);
        self.line2.center = CGPointMake(linesTargetX, centerY);
        self.line3.center = CGPointMake(linesTargetX, centerY + 6.0);
    }
}

// ================= 【液态交互手势】 =================
- (void)panGestureOccurred:(UIPanGestureRecognizer *)sender {
    CGPoint touchLocation = [sender locationInView:self];
    if (sender.state == UIGestureRecognizerStateBegan) {
        self.onBeforeDrag = self.isOn;
        self.dragging = YES;
        [UIView animateWithDuration:0.2 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
            self.knobView.transform = CGAffineTransformMakeScale(0.8, 0.8);
        } completion:nil];
    } else if (sender.state == UIGestureRecognizerStateChanged) {
        self.moved = YES;
        if (touchLocation.x > self.bounds.size.width / 2 && !self.isOn) { self.on = YES; }
        else if (touchLocation.x < self.bounds.size.width / 2 && self.isOn) { self.on = NO; }
    } else if (sender.state == UIGestureRecognizerStateEnded || sender.state == UIGestureRecognizerStateCancelled || sender.state == UIGestureRecognizerStateFailed) {
        self.dragging = NO;
        self.moved = NO;
        [UIView animateWithDuration:0.4 delay:0 usingSpringWithDamping:0.6 initialSpringVelocity:0.8 options:UIViewAnimationOptionCurveEaseOut animations:^{
            self.knobView.transform = CGAffineTransformIdentity;
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
    BOOL shouldAnimate = (self.window != nil);
    [self _setOn:on animated:shouldAnimate];
}

- (void)setOn:(BOOL)on animated:(BOOL)animated {
    if (_on == on) return;
    _on = on;
    [self _setOn:on animated:animated];
}

// ================= 【核心：#C0D6C4 vs 干净浅灰配色】 =================
- (void)_setOn:(BOOL)on animated:(BOOL)animated {
    if (self.changeAction && !_shouldSkipChangeAction && animated) {
        self.changeAction(on, !self.isMoved);
    }

    CGFloat margin = [self knobMargin];
    CGFloat knobRadius = self.knobView.bounds.size.width / 2.0;
    CGFloat centerY = self.bounds.size.height / 2.0;
    CGFloat targetX = on ? (self.bounds.size.width - margin - knobRadius) : (margin + knobRadius);
    CGFloat linesTargetX = on ? (targetX - knobRadius - 10) : (targetX + knobRadius + 10);

    // 【为你量身定制的配色】
    // 轨道开启：你指定的浅豆绿 #C0D6C4 (RGB: 192, 214, 196)
    UIColor *onTrackColor = [UIColor colorWithRed:192.0/255.0 green:214.0/255.0 blue:196.0/255.0 alpha:1.0];
    // 轨道关闭：依然是干净的原生浅灰
    UIColor *offTrackColor = [UIColor colorWithRed:0.92 green:0.92 blue:0.94 alpha:1.0];

    // 三道杠颜色：全部保持纯白
    UIColor *colorWhite = [UIColor whiteColor];
    UIColor *offLineColor = [UIColor colorWithRed:0.75 green:0.75 blue:0.78 alpha:1.0]; // 关闭时干净浅灰

    // 滑块阴影色 (配合 #C0D6C4 的柔和色调，做稍微深一点点的同色系自然阴影)
    UIColor *onShadowColor = [UIColor colorWithRed:140.0/255.0 green:160.0/255.0 blue:144.0/255.0 alpha:0.4];

    // 滑块：两态都保持干净的亮银色金属质感
    NSArray *knobColors = @[(id)[UIColor whiteColor].CGColor, (id)[UIColor colorWithRed:0.90 green:0.90 blue:0.92 alpha:1.0].CGColor];

    BOOL doAnimate = animated && _shouldAnimateImportant;
    CGFloat duration = doAnimate ? 0.45 : 0.0;

    if (doAnimate) {
        if (!self.isDragging) {
            self.knobView.transform = CGAffineTransformMakeScale(0.75, 0.75);
        }

        [UIView transitionWithView:self duration:duration options:UIViewAnimationOptionTransitionCrossDissolve animations:^{
            self.trackView.backgroundColor = on ? onTrackColor : offTrackColor;
            self.knobGrad.colors = knobColors;

            // 内部能量核心渐亮
            self.innerIndicator.opacity = on ? 1.0 : 0.0;

            // 外部阴影 (在浅色背景下不再用死黑，而是通透的同色系阴影)
            self.knobView.layer.shadowColor = on ? onShadowColor.CGColor : [UIColor blackColor].CGColor;
            self.knobView.layer.shadowOpacity = 0.0;
            self.knobView.layer.shadowRadius = on ? 5.0 : 4.0;
        } completion:nil];

        [UIView animateWithDuration:duration delay:0 usingSpringWithDamping:0.65 initialSpringVelocity:0.8 options:UIViewAnimationOptionCurveEaseInOut | UIViewAnimationOptionAllowUserInteraction animations:^{
            self.knobView.center = CGPointMake(targetX, centerY);
            self.knobView.transform = CGAffineTransformIdentity;
        } completion:nil];

        // 三道杠波浪 (纯白色彩)
        NSArray *lines = @[self.line1, self.line2, self.line3];
        NSArray *auroraColors = @[colorWhite, colorWhite, colorWhite];

        for (int i = 0; i < lines.count; i++) {
            UIView *line = lines[i];
            UIColor *targetColor = on ? auroraColors[i] : offLineColor;
            NSTimeInterval delay = i * 0.05;

            [UIView animateWithDuration:0.55 delay:delay usingSpringWithDamping:0.6 initialSpringVelocity:1.0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
                line.center = CGPointMake(linesTargetX, line.center.y);
                line.backgroundColor = targetColor;
                // 白线在浅色背景下加微弱的发光增强对比
                line.layer.shadowColor = on ? targetColor.CGColor : [UIColor clearColor].CGColor;
                line.layer.shadowOpacity = 0.0;
            } completion:nil];
        }
    } else {
        self.knobView.center = CGPointMake(targetX, centerY);
        self.knobView.transform = CGAffineTransformIdentity;

        self.trackView.backgroundColor = on ? onTrackColor : offTrackColor;
        self.knobGrad.colors = knobColors;

        self.innerIndicator.opacity = on ? 1.0 : 0.0;
        self.knobView.layer.shadowColor = on ? onShadowColor.CGColor : [UIColor blackColor].CGColor;
        self.knobView.layer.shadowOpacity = 0.0;
        self.knobView.layer.shadowRadius = on ? 5.0 : 4.0;

        self.line1.center = CGPointMake(linesTargetX, centerY - 6.0);
        self.line2.center = CGPointMake(linesTargetX, centerY);
        self.line3.center = CGPointMake(linesTargetX, centerY + 6.0);

        NSArray *lines = @[self.line1, self.line2, self.line3];
        NSArray *auroraColors = @[colorWhite, colorWhite, colorWhite];

        for (int i = 0; i < lines.count; i++) {
            UIView *line = lines[i];
            UIColor *targetColor = on ? auroraColors[i] : offLineColor;
            line.backgroundColor = targetColor;
            line.layer.shadowColor = on ? targetColor.CGColor : [UIColor clearColor].CGColor;
            line.layer.shadowOpacity = 0.0;
        }
    }
}

- (void)blockChangeActionAnimated:(BOOL)animated { _shouldSkipChangeAction = YES; }
- (void)unblockChangeAction { _shouldSkipChangeAction = NO; }
@end
