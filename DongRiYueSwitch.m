//
//  DayNightSwitch.m
//  DayNightSwitch (逻辑完全反转：关闭=太阳，打开=月亮)
//

#import "DongRiYueSwitch.h"

#define ColorHex(hexValue) [UIColor colorWithRed:((float)((hexValue & 0xFF0000) >> 16))/255.0 green:((float)((hexValue & 0xFF00) >> 8))/255.0 blue:((float)(hexValue & 0xFF))/255.0 alpha:1.0]
#define ColorHexA(hexValue, a) [UIColor colorWithRed:((float)((hexValue & 0xFF0000) >> 16))/255.0 green:((float)((hexValue & 0xFF00) >> 8))/255.0 blue:((float)(hexValue & 0xFF))/255.0 alpha:(a)]

@interface DongRiYueSwitch ()

@property (nonatomic, strong) UIView *trackView;
@property (nonatomic, strong) UIView *dayBgView;
@property (nonatomic, strong) UIView *nightBgView;

@property (nonatomic, strong) UIView *circleContainer;
@property (nonatomic, strong) UIView *sunMoonContainer;
@property (nonatomic, strong) UIView *moonView;
@property (nonatomic, strong) UIView *haloView;

@property (nonatomic, strong) UIView *cloudsContainer;
@property (nonatomic, strong) UIView *starsClusterContainer;
@property (nonatomic, strong) UIView *nightSkyEffectsContainer;

@property (nonatomic, assign) CGFloat em;

@property (nonatomic, assign, getter=isMoved) BOOL moved;
@property (nonatomic, assign, getter=isDragging) BOOL dragging;
@property (nonatomic, assign, getter=isOnBeforeDrag) BOOL onBeforeDrag;
@property (nonatomic, assign, getter=isHovering) BOOL hovering;

@end

@implementation DongRiYueSwitch {
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

    _em = self.bounds.size.height / 2.5;

    // 1. 底层轨道
    self.trackView = [[UIView alloc] initWithFrame:self.bounds];
    self.trackView.layer.cornerRadius = self.bounds.size.height / 2.0;
    self.trackView.layer.masksToBounds = YES;
    self.trackView.layer.borderWidth = 1.0;
    self.trackView.layer.borderColor = [UIColor colorWithWhite:0 alpha:0.15].CGColor;
    [self addSubview:self.trackView];

    // 2. 白天背景层
    self.dayBgView = [[UIView alloc] initWithFrame:self.bounds];
    self.dayBgView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    CAGradientLayer *dayGrad = [CAGradientLayer layer];
    dayGrad.frame = self.dayBgView.bounds;
    dayGrad.colors = @[(__bridge id)ColorHex(0x3d7eae).CGColor, (__bridge id)ColorHex(0x5490c0).CGColor];
    [self.dayBgView.layer addSublayer:dayGrad];
    [self.trackView addSubview:self.dayBgView];

    // 3. 夜晚背景层
    self.nightBgView = [[UIView alloc] initWithFrame:self.bounds];
    self.nightBgView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    CAGradientLayer *nightGrad = [CAGradientLayer layer];
    nightGrad.frame = self.nightBgView.bounds;
    nightGrad.colors = @[(__bridge id)ColorHex(0x1d1f2c).CGColor, (__bridge id)ColorHex(0x2d3142).CGColor];
    [self.nightBgView.layer addSublayer:nightGrad];
    self.nightBgView.alpha = 0.0;
    [self.trackView addSubview:self.nightBgView];

    // 4. 构建内部组件
    [self setupNightSkyEffects];
    [self setupStarsCluster];
    [self setupClouds];

    // 5. 轨道光环与圆盘容器
    CGFloat circleDia = 3.375 * _em;
    CGFloat offset = (circleDia - self.bounds.size.height) / 2.0 * -1;
    self.circleContainer = [[UIView alloc] initWithFrame:CGRectMake(offset, offset, circleDia, circleDia)];
    self.circleContainer.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.1];
    self.circleContainer.layer.cornerRadius = circleDia / 2.0;
    self.circleContainer.userInteractionEnabled = NO;

    CGFloat r2Dia = circleDia + 0.625 * 2 * _em;
    UIView *r2 = [[UIView alloc] initWithFrame:CGRectMake((circleDia - r2Dia)/2.0, (circleDia - r2Dia)/2.0, r2Dia, r2Dia)];
    r2.layer.cornerRadius = r2Dia/2.0;
    r2.backgroundColor = [UIColor clearColor];
    r2.layer.borderWidth = 0.625 * _em;
    r2.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.1].CGColor;
    [self.circleContainer addSubview:r2];

    CGFloat r1Dia = circleDia + 1.25 * 2 * _em;
    UIView *r1 = [[UIView alloc] initWithFrame:CGRectMake((circleDia - r1Dia)/2.0, (circleDia - r1Dia)/2.0, r1Dia, r1Dia)];
    r1.layer.cornerRadius = r1Dia/2.0;
    r1.backgroundColor = [UIColor clearColor];
    r1.layer.borderWidth = 0.625 * _em;
    r1.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.1].CGColor;
    [self.circleContainer addSubview:r1];

    // 6. 太阳与月亮
    CGFloat sunMoonDia = 2.125 * _em;
    self.sunMoonContainer = [[UIView alloc] initWithFrame:CGRectMake((circleDia - sunMoonDia)/2.0, (circleDia - sunMoonDia)/2.0, sunMoonDia, sunMoonDia)];
    self.sunMoonContainer.layer.cornerRadius = sunMoonDia / 2.0;
    self.sunMoonContainer.backgroundColor = ColorHex(0xecca2f);
    self.sunMoonContainer.layer.masksToBounds = YES;

    self.sunMoonContainer.layer.shadowColor = [UIColor blackColor].CGColor;
    self.sunMoonContainer.layer.shadowOffset = CGSizeMake(0.062 * _em, 0.125 * _em);
    self.sunMoonContainer.layer.shadowOpacity = 0.25;
    self.sunMoonContainer.layer.shadowRadius = 0.125 * _em;

    self.haloView = [[UIView alloc] initWithFrame:CGRectInset(self.sunMoonContainer.bounds, -5, -5)];
    self.haloView.layer.cornerRadius = self.haloView.bounds.size.width / 2.0;
    self.haloView.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.2];
    self.haloView.alpha = 0.0;
    [self.sunMoonContainer addSubview:self.haloView];

    self.moonView = [[UIView alloc] initWithFrame:self.sunMoonContainer.bounds];
    self.moonView.layer.cornerRadius = sunMoonDia / 2.0;
    self.moonView.backgroundColor = ColorHex(0xc4c9d1);
    self.moonView.transform = CGAffineTransformMakeTranslation(sunMoonDia, 0);

    [self setupMoonSpots];

    [self.sunMoonContainer addSubview:self.moonView];
    [self.circleContainer addSubview:self.sunMoonContainer];

    [self.trackView addSubview:self.circleContainer];

    [self layoutForCurrentStateAnimated:NO];

    // ================= 手势事件绑定 =================
    UITapGestureRecognizer *tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapGestureOccurred:)];
    tapGesture.cancelsTouchesInView = NO;
    [self addGestureRecognizer:tapGesture];

    UIPanGestureRecognizer *panGesture = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(panGestureOccurred:)];
    panGesture.cancelsTouchesInView = YES;
    [self addGestureRecognizer:panGesture];
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    [self dns_updateLoopingAnimations];
}

- (void)dns_updateLoopingAnimations {
    if (self.window && self.isOn) {
        [self dns_startLoopingAnimations];
    } else {
        [self dns_stopAllLoopingAnimations];
    }
}

- (void)dns_startLoopingAnimations {
    if (!self.window || !self.isOn) {
        [self dns_stopAllLoopingAnimations];
        return;
    }

    NSArray<NSNumber *> *delays = @[@0.0, @0.3, @0.6, @0.9, @1.2];

    for (NSUInteger i = 0; i < self.starsClusterContainer.subviews.count; i++) {
        UIView *star = self.starsClusterContainer.subviews[i];
        [star.layer removeAnimationForKey:@"twinkle"];
        [star.layer removeAnimationForKey:@"fade"];

        CGFloat delay = i < delays.count ? delays[i].doubleValue : 0.0;

        CABasicAnimation *twinkle = [CABasicAnimation animationWithKeyPath:@"transform.scale"];
        twinkle.fromValue = @(1.0);
        twinkle.toValue = @(1.2);
        twinkle.duration = 0.5;
        twinkle.autoreverses = YES;
        twinkle.repeatCount = HUGE_VALF;
        twinkle.beginTime = CACurrentMediaTime() + delay;
        [star.layer addAnimation:twinkle forKey:@"twinkle"];

        CABasicAnimation *fade = [CABasicAnimation animationWithKeyPath:@"opacity"];
        fade.fromValue = @(0.3);
        fade.toValue = @(1.0);
        fade.duration = 0.5;
        fade.autoreverses = YES;
        fade.repeatCount = HUGE_VALF;
        fade.beginTime = CACurrentMediaTime() + delay;
        [star.layer addAnimation:fade forKey:@"fade"];
    }

    for (UIView *particle in [self.nightSkyEffectsContainer.subviews copy]) {
        [particle removeFromSuperview];
    }
    [self addParticleToSky:@"shootingStar" w:2 h:2 color:0xFFFFFF delay:0 duration:2 type:1];
    [self addParticleToSky:@"shootingStar2" w:1 h:1 color:0xFFFFFF delay:1 duration:3 type:1];
    [self addParticleToSky:@"meteor" w:3 h:3 color:0xFFD700 delay:2 duration:4 type:2];
    [self addParticleToSky:@"comet1" w:2 h:2 color:0xFFFFFF delay:0 duration:4 type:3];
    [self addParticleToSky:@"comet2" w:2 h:2 color:0xFFFFFF delay:2 duration:6 type:3];
}

- (void)dns_stopAllLoopingAnimations {
    for (UIView *star in self.starsClusterContainer.subviews) {
        [star.layer removeAnimationForKey:@"twinkle"];
        [star.layer removeAnimationForKey:@"fade"];
    }

    for (UIView *particle in [self.nightSkyEffectsContainer.subviews copy]) {
        [particle.layer removeAllAnimations];
        for (CALayer *sublayer in [particle.layer.sublayers copy]) {
            [sublayer removeAllAnimations];
        }
        [particle removeFromSuperview];
    }
}

// ================= 【手势事件接管】 =================
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
        // 跟随手指滑动位置实时切换开关状态 (右边=ON, 左边=OFF)
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
        if (self.isOn != self.isOnBeforeDrag && self.changeAction) {
            self.changeAction(self.isOn, YES);
        }
    }
}

// ================= 【各种视觉层设置】 =================
- (void)setupClouds {
    self.cloudsContainer = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.bounds.size.width, self.bounds.size.height)];
    self.cloudsContainer.userInteractionEnabled = NO;
    [self.trackView addSubview:self.cloudsContainer];

    UIColor *cloudsColor = ColorHex(0xf3fdff);
    UIColor *backCloudsColor = ColorHex(0xaacadf);
    CGFloat r = 1.25 * _em;

    UIView *baseCloud = [[UIView alloc] initWithFrame:CGRectMake(0.312 * _em, self.bounds.size.height - 0.625 * _em, r, r)];
    baseCloud.backgroundColor = cloudsColor;
    baseCloud.layer.cornerRadius = r / 2.0;
    [self.cloudsContainer addSubview:baseCloud];

    CGFloat shadowData[15][3] = {
        {0.937, 0.312, 1},  {-0.312, -0.312, 0}, {1.437, 0.375, 1},
        {0.5, -0.125, 0},   {2.187, 0, 1},       {1.25, -0.062, 0},
        {2.937, 0.312, 1},  {2.0, -0.312, 0},    {3.625, -0.062, 1},
        {2.625, 0, 0},      {4.5, -0.312, 1},    {3.375, -0.437, 0},
        {4.625, -1.75, 1},  {4.0, -0.625, 0},    {4.125, -2.125, 0}
    };

    for (int i = 0; i < 15; i++) {
        UIView *shadowPart = [[UIView alloc] initWithFrame:CGRectMake(shadowData[i][0] * _em, shadowData[i][1] * _em, r, r)];
        shadowPart.layer.cornerRadius = r / 2.0;
        shadowPart.backgroundColor = shadowData[i][2] == 1 ? cloudsColor : backCloudsColor;

        if (i == 12 || i == 14) {
            CGFloat expandedR = r + 0.437 * _em * 2;
            shadowPart.frame = CGRectMake(shadowData[i][0] * _em - 0.437*_em, shadowData[i][1] * _em - 0.437*_em, expandedR, expandedR);
            shadowPart.layer.cornerRadius = expandedR / 2.0;
        }
        if (shadowData[i][2] == 0) { [baseCloud insertSubview:shadowPart atIndex:0]; }
        else { [baseCloud addSubview:shadowPart]; }
    }
}

- (void)setupMoonSpots {
    UIColor *spotColor = ColorHex(0x959db1);
    UIView *s1 = [[UIView alloc] initWithFrame:CGRectMake(0.312*_em, 0.75*_em, 0.75*_em, 0.75*_em)];
    s1.layer.cornerRadius = 0.75*_em/2.0; s1.backgroundColor = spotColor; [self.moonView addSubview:s1];

    UIView *s2 = [[UIView alloc] initWithFrame:CGRectMake(1.375*_em, 0.937*_em, 0.375*_em, 0.375*_em)];
    s2.layer.cornerRadius = 0.375*_em/2.0; s2.backgroundColor = spotColor; [self.moonView addSubview:s2];

    UIView *s3 = [[UIView alloc] initWithFrame:CGRectMake(0.812*_em, 0.312*_em, 0.25*_em, 0.25*_em)];
    s3.layer.cornerRadius = 0.25*_em/2.0; s3.backgroundColor = spotColor; [self.moonView addSubview:s3];
}

- (void)setupStarsCluster {
    self.starsClusterContainer = [[UIView alloc] initWithFrame:CGRectMake(0.312*_em, -self.bounds.size.height, 2.75*_em, self.bounds.size.height)];
    self.starsClusterContainer.alpha = 0;
    [self.trackView addSubview:self.starsClusterContainer];

    CGFloat starPositions[5][3] = {{0.2, 0.2, 0.0}, {0.3, 0.55, 0.3}, {0.4, 0.8, 0.6}, {0.6, 0.3, 0.9}, {0.7, 0.65, 1.2}};
    for (int i=0; i<5; i++) {
        UIView *star = [[UIView alloc] initWithFrame:CGRectMake(starPositions[i][1] * self.starsClusterContainer.bounds.size.width, starPositions[i][0] * self.starsClusterContainer.bounds.size.height, 2, 2)];
        star.backgroundColor = [UIColor whiteColor]; star.layer.cornerRadius = 1;
        star.layer.shadowColor = [UIColor whiteColor].CGColor; star.layer.shadowRadius = 4;
        star.layer.shadowOpacity = 1; star.layer.shadowOffset = CGSizeZero;
        [self.starsClusterContainer addSubview:star];

    }
}

- (void)setupNightSkyEffects {
    self.nightSkyEffectsContainer = [[UIView alloc] initWithFrame:self.bounds];
    self.nightSkyEffectsContainer.alpha = 0;
    [self.trackView addSubview:self.nightSkyEffectsContainer];
}

- (void)addParticleToSky:(NSString *)name w:(CGFloat)w h:(CGFloat)h color:(uint)color delay:(CGFloat)delay duration:(CGFloat)duration type:(int)type {
    UIView *particle = [[UIView alloc] initWithFrame:CGRectMake(0, 0, w, h)];
    particle.backgroundColor = ColorHex(color); particle.layer.cornerRadius = w / 2.0;

    if (type == 3) {
        CAGradientLayer *grad = [CAGradientLayer layer]; grad.frame = particle.bounds;
        grad.colors = @[(__bridge id)ColorHex(0xFFFFFF).CGColor, (__bridge id)[UIColor clearColor].CGColor];
        grad.startPoint = CGPointMake(0, 0.5); grad.endPoint = CGPointMake(1, 0.5);
        [particle.layer addSublayer:grad]; particle.backgroundColor = [UIColor clearColor];
    }

    [self.nightSkyEffectsContainer addSubview:particle];

    CAKeyframeAnimation *anim = [CAKeyframeAnimation animationWithKeyPath:@"transform"];
    NSMutableArray *values = [NSMutableArray array];
    if (type == 1) {
        particle.center = CGPointMake(-self.bounds.size.width * 0.1, self.bounds.size.height * 0.2);
        [values addObject:[NSValue valueWithCATransform3D:CATransform3DRotate(CATransform3DIdentity, M_PI_4, 0, 0, 1)]];
        [values addObject:[NSValue valueWithCATransform3D:CATransform3DTranslate(CATransform3DRotate(CATransform3DIdentity, M_PI_4, 0, 0, 1), 150, 150, 0)]];
    } else if (type == 2) {
        particle.center = CGPointMake(self.bounds.size.width * 0.5, -self.bounds.size.height * 0.1);
        [values addObject:[NSValue valueWithCATransform3D:CATransform3DScale(CATransform3DIdentity, 1.0, 1.0, 1)]];
        [values addObject:[NSValue valueWithCATransform3D:CATransform3DScale(CATransform3DTranslate(CATransform3DIdentity, 0, 150, 0), 0.3, 0.3, 1)]];
    } else if (type == 3) {
        CGFloat startY = [name isEqualToString:@"comet1"] ? 0.3 : 0.5;
        particle.center = CGPointMake(-self.bounds.size.width * 0.1, self.bounds.size.height * startY);
        [values addObject:[NSValue valueWithCATransform3D:CATransform3DScale(CATransform3DRotate(CATransform3DIdentity, -M_PI_4, 0, 0, 1), 1.0, 1.0, 1)]];
        [values addObject:[NSValue valueWithCATransform3D:CATransform3DScale(CATransform3DTranslate(CATransform3DRotate(CATransform3DIdentity, -M_PI_4, 0, 0, 1), 200, 200, 0), 0.2, 0.2, 1)]];
    }
    anim.values = values;

    CAKeyframeAnimation *opacityAnim = [CAKeyframeAnimation animationWithKeyPath:@"opacity"];
    opacityAnim.values = type == 3 ? @[@0, @1, @1, @0] : @[@1, @0];
    opacityAnim.keyTimes = type == 3 ? @[@0, @0.1, @0.9, @1.0] : @[@0, @1];

    CAAnimationGroup *group = [CAAnimationGroup animation];
    group.animations = @[anim, opacityAnim]; group.duration = duration;
    group.repeatCount = HUGE_VALF; group.beginTime = CACurrentMediaTime() + delay; group.fillMode = kCAFillModeForwards;
    [particle.layer addAnimation:group forKey:name];
}

// ================= 【核心状态流转】 =================
- (void)setOn:(BOOL)on { [self setOn:on animated:NO]; }

- (void)setOn:(BOOL)on animated:(BOOL)animated {
    if (_on == on) return;
    _on = on;

    if (self.changeAction && !_shouldSkipChangeAction && animated) {
        self.changeAction(on, !self.isMoved);
    }
    BOOL doAnimate = animated && _shouldAnimateImportant;

    if (doAnimate) {
        CAMediaTimingFunction *timing = [CAMediaTimingFunction functionWithControlPoints:0.0 :-0.02 :0.4 :1.25];
        [CATransaction begin];
        [CATransaction setAnimationDuration:0.5];
        [CATransaction setAnimationTimingFunction:timing];

        [UIView animateWithDuration:0.5 delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
            [self layoutForCurrentStateAnimated:YES];
        } completion:^(BOOL finished) {
            [self dns_updateLoopingAnimations];
        }];

        [CATransaction commit];
    } else {
        [self layoutForCurrentStateAnimated:NO];
        [self dns_updateLoopingAnimations];
    }
}

- (void)animateHoverState {
    [UIView animateWithDuration:0.3 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
        if (self.isHovering) {
            self.sunMoonContainer.transform = CGAffineTransformRotate(CGAffineTransformMakeScale(1.1, 1.1), 5 * M_PI / 180.0);
            self.haloView.alpha = 1.0;
            // ON (月亮) 状态下悬浮，月球旋转；OFF (太阳) 下，云朵缩放
            if (self.isOn) {
                self.moonView.transform = CGAffineTransformRotate(CGAffineTransformMakeTranslation(0, 0), 15 * M_PI / 180.0);
                for (UIView *spot in self.moonView.subviews) { spot.backgroundColor = ColorHex(0x7a7f8c); }
            }
            if (!self.isOn) { self.cloudsContainer.transform = CGAffineTransformScale(CGAffineTransformMakeTranslation(15, 0), 1.02, 1.02); }

            CGFloat targetX = self.isOn ? (self.bounds.size.width - self.circleContainer.bounds.size.width - 0.187*_em) : 0.187*_em;
            self.circleContainer.center = CGPointMake(targetX + self.circleContainer.bounds.size.width/2.0, self.bounds.size.height/2.0);
        } else {
            self.sunMoonContainer.transform = CGAffineTransformIdentity;
            self.haloView.alpha = 0.0;
            self.moonView.transform = self.isOn ? CGAffineTransformIdentity : CGAffineTransformMakeTranslation(2.125*_em, 0);
            for (UIView *spot in self.moonView.subviews) { spot.backgroundColor = ColorHex(0x959db1); }
            self.cloudsContainer.transform = CGAffineTransformIdentity;
            [self layoutForCurrentStateAnimated:NO];
        }
    } completion:nil];
}

- (void)layoutForCurrentStateAnimated:(BOOL)animated {
    CGFloat circleDia = self.circleContainer.bounds.size.width;
    CGFloat offset = (circleDia - self.bounds.size.height) / 2.0 * -1;

    // 【反转显示】ON = 黑夜显示，白天隐藏；OFF = 白天显示，黑夜隐藏
    self.dayBgView.alpha = self.isOn ? 0.0 : 1.0;
    self.nightBgView.alpha = self.isOn ? 1.0 : 0.0;

    CGFloat targetX = self.isOn ? (self.bounds.size.width - offset - circleDia) : offset;
    if (!self.isHovering) { self.circleContainer.frame = CGRectMake(targetX, offset, circleDia, circleDia); }

    // 【反转控制】ON(月亮) 则 Identity 显示；OFF(太阳) 则 Translate 移走
    self.moonView.transform = self.isOn ? CGAffineTransformIdentity : CGAffineTransformMakeTranslation(2.125*_em, 0);
    self.cloudsContainer.center = CGPointMake(self.cloudsContainer.center.x, self.isOn ? (self.bounds.size.height/2.0 + 4.062*_em) : self.bounds.size.height/2.0);
    self.starsClusterContainer.center = CGPointMake(self.starsClusterContainer.center.x, self.isOn ? self.bounds.size.height/2.0 : -self.bounds.size.height/2.0);

    self.starsClusterContainer.alpha = self.isOn ? 1.0 : 0.0;
    self.nightSkyEffectsContainer.alpha = self.isOn ? 1.0 : 0.0;
}

// ================= 【Tweak 协议方法】 =================
- (CGFloat)knobMargin { return 3.0; }
- (void)blockChangeActionAnimated:(BOOL)animated { _shouldSkipChangeAction = YES; }
- (void)unblockChangeAction { _shouldSkipChangeAction = NO; }

- (void)dealloc {
    [self dns_stopAllLoopingAnimations];
}

@end
