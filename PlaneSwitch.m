//
//  PlaneSwitch.m
//  PlaneSwitch (恢复高清系统飞机 + 向右平飞 + 永不消失的云朵)
//

#import "PlaneSwitch.h"

#define ColorHex(hexValue) [UIColor colorWithRed:((float)((hexValue & 0xFF0000) >> 16))/255.0 green:((float)((hexValue & 0xFF00) >> 8))/255.0 blue:((float)(hexValue & 0xFF))/255.0 alpha:1.0]
#define ColorHexA(hexValue, a) [UIColor colorWithRed:((float)((hexValue & 0xFF0000) >> 16))/255.0 green:((float)((hexValue & 0xFF00) >> 8))/255.0 blue:((float)(hexValue & 0xFF))/255.0 alpha:(a)]

@interface PlaneSwitch ()

@property (nonatomic, strong) UIView *trackView;
@property (nonatomic, strong) UIView *streetBgView;
@property (nonatomic, strong) UIView *skyBgView;

@property (nonatomic, strong) UIView *runwayContainer;
@property (nonatomic, strong) UIView *cloudsContainer;

@property (nonatomic, strong) UIView *cloud1;
@property (nonatomic, strong) UIView *cloud2;
@property (nonatomic, strong) NSMutableArray<UIView *> *runwayLights;

@property (nonatomic, strong) UIView *knobView;
// 恢复为 UIImageView，重新使用系统自带的高清大客机
@property (nonatomic, strong) UIImageView *planeIcon;

@property (nonatomic, assign) CGFloat em;

@property (nonatomic, assign, getter=isMoved) BOOL moved;
@property (nonatomic, assign, getter=isDragging) BOOL dragging;
@property (nonatomic, assign, getter=isOnBeforeDrag) BOOL onBeforeDrag;
@property (nonatomic, assign, getter=isHovering) BOOL hovering;

@end

@implementation PlaneSwitch {
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

    _em = self.bounds.size.height / 25.0;
    self.runwayLights = [NSMutableArray array];

    self.trackView = [[UIView alloc] initWithFrame:self.bounds];
    self.trackView.layer.cornerRadius = self.bounds.size.height / 2.0;
    self.trackView.layer.masksToBounds = YES;
    [self addSubview:self.trackView];

    self.streetBgView = [[UIView alloc] initWithFrame:self.bounds];
    self.streetBgView.backgroundColor = ColorHex(0x6B6D76);
    self.streetBgView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.trackView addSubview:self.streetBgView];

    self.skyBgView = [[UIView alloc] initWithFrame:self.bounds];
    self.skyBgView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    CAGradientLayer *skyGrad = [CAGradientLayer layer];
    skyGrad.frame = self.skyBgView.bounds;

    UIColor *skyC1 = ColorHex(0x60A7FA);
    UIColor *skyC2 = ColorHex(0x2F8EFC);
    skyGrad.colors = @[(id)skyC1.CGColor, (id)skyC2.CGColor];
    skyGrad.startPoint = CGPointMake(0, 0.5);
    skyGrad.endPoint = CGPointMake(1, 0.5);
    [self.skyBgView.layer addSublayer:skyGrad];
    self.skyBgView.alpha = 0.0;
    [self.trackView addSubview:self.skyBgView];

    [self setupClouds];
    [self setupRunway];

    CGFloat knobDia = 23.0 * _em;
    self.knobView = [[UIView alloc] initWithFrame:CGRectMake(1 * _em, 1 * _em, knobDia, knobDia)];
    self.knobView.layer.cornerRadius = knobDia / 2.0;
    self.knobView.backgroundColor = [UIColor whiteColor];

    // ================== 【核心修复：接回高清大客机】 ==================
    self.planeIcon = [[UIImageView alloc] initWithFrame:CGRectInset(self.knobView.bounds, 4*_em, 4*_em)];
    if (@available(iOS 13.0, *)) {
        // 调用 iOS 系统高清客机图标
        self.planeIcon.image = [UIImage systemImageNamed:@"airplane"];
    }
    self.planeIcon.contentMode = UIViewContentModeScaleAspectFit;
    self.planeIcon.tintColor = ColorHex(0x6B6D76);

    // 原生大客机是机头朝上的，我们顺时针旋转 90 度，让它完美向右平飞
    self.planeIcon.transform = CGAffineTransformMakeRotation(0.0 * M_PI / 180.0);

    [self.knobView addSubview:self.planeIcon];
    [self.trackView addSubview:self.knobView];

    [self layoutForCurrentStateAnimated:NO];

    UITapGestureRecognizer *tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapGestureOccurred:)];
    tapGesture.cancelsTouchesInView = NO;
    [self addGestureRecognizer:tapGesture];

    UIPanGestureRecognizer *panGesture = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(panGestureOccurred:)];
    panGesture.cancelsTouchesInView = NO;
    [self addGestureRecognizer:panGesture];
}

// 唤醒动画：防止系统回收云朵和跑马灯
- (void)didMoveToWindow {
    [super didMoveToWindow];
    if (self.window) {
        [self startAllLoopingAnimations];
    }
}

- (void)startAllLoopingAnimations {
    [self.cloud1.layer removeAnimationForKey:@"cloudMove"];
    CABasicAnimation *c1Anim = [CABasicAnimation animationWithKeyPath:@"transform.translation.x"];
    c1Anim.fromValue = @(0);
    c1Anim.toValue = @(-self.bounds.size.width - 24*_em);
    c1Anim.duration = 2.0;
    c1Anim.repeatCount = HUGE_VALF;
    [self.cloud1.layer addAnimation:c1Anim forKey:@"cloudMove"];

    [self.cloud2.layer removeAnimationForKey:@"cloudMove"];
    CABasicAnimation *c2Anim = [CABasicAnimation animationWithKeyPath:@"transform.translation.x"];
    c2Anim.fromValue = @(0);
    c2Anim.toValue = @(-self.bounds.size.width - 24*_em);
    c2Anim.duration = 2.0;
    c2Anim.repeatCount = HUGE_VALF;
    c2Anim.timeOffset = 1.0;
    [self.cloud2.layer addAnimation:c2Anim forKey:@"cloudMove"];

    UIColor *cBright = ColorHexA(0xFFE900, 1.0);
    UIColor *cDim = ColorHexA(0xFFE900, 0.3);
    id bright = (id)cBright.CGColor;
    id dim = (id)cDim.CGColor;

    for (int i = 0; i < self.runwayLights.count; i++) {
        UIView *light = self.runwayLights[i];
        [light.layer removeAnimationForKey:@"lightsBlink"];

        int col = i / 2;
        CAKeyframeAnimation *anim = [CAKeyframeAnimation animationWithKeyPath:@"backgroundColor"];
        if (col == 0) {
            anim.values = @[dim, bright, dim, dim];
            anim.keyTimes = @[@0, @0.2, @0.4, @1];
        } else if (col == 1) {
            anim.values = @[dim, dim, bright, dim, dim];
            anim.keyTimes = @[@0, @0.4, @0.55, @0.75, @1];
        } else {
            anim.values = @[dim, dim, dim, bright, dim];
            anim.keyTimes = @[@0, @0.6, @0.8, @0.9, @1];
        }

        anim.duration = 2.0;
        anim.repeatCount = HUGE_VALF;
        [light.layer addAnimation:anim forKey:@"lightsBlink"];
    }
}

- (void)setupRunway {
    self.runwayContainer = [[UIView alloc] initWithFrame:self.bounds];
    self.runwayContainer.userInteractionEnabled = NO;
    [self.trackView addSubview:self.runwayContainer];

    UIColor *streetLine = ColorHex(0xA8AAB4);
    UIColor *streetLineMid = ColorHex(0xC0C2C8);

    UIView *topLine = [[UIView alloc] initWithFrame:CGRectMake(6*_em, 4*_em, 42*_em, 1*_em)];
    topLine.backgroundColor = streetLine;
    [self.runwayContainer addSubview:topLine];

    UIView *bottomLine = [[UIView alloc] initWithFrame:CGRectMake(6*_em, 20*_em, 42*_em, 1*_em)];
    bottomLine.backgroundColor = streetLine;
    [self.runwayContainer addSubview:bottomLine];

    for (int i = 0; i < 5; i++) {
        UIView *dash = [[UIView alloc] initWithFrame:CGRectMake((21 + i * 5) * _em, 12 * _em, 3 * _em, 1 * _em)];
        dash.backgroundColor = streetLineMid;
        [self.runwayContainer addSubview:dash];
    }

    [self addRunwayLightAtPoint:CGPointMake(23*_em, 1*_em)];
    [self addRunwayLightAtPoint:CGPointMake(23*_em, 22*_em)];

    [self addRunwayLightAtPoint:CGPointMake(31*_em, 1*_em)];
    [self addRunwayLightAtPoint:CGPointMake(31*_em, 22*_em)];

    [self addRunwayLightAtPoint:CGPointMake(39*_em, 1*_em)];
    [self addRunwayLightAtPoint:CGPointMake(39*_em, 22*_em)];
}

- (void)addRunwayLightAtPoint:(CGPoint)point {
    UIView *light = [[UIView alloc] initWithFrame:CGRectMake(point.x, point.y, 2*_em, 2*_em)];
    light.layer.cornerRadius = 1 * _em;
    light.backgroundColor = ColorHexA(0xFFE900, 0.3);
    [self.runwayContainer addSubview:light];
    [self.runwayLights addObject:light];
}

- (void)setupClouds {
    self.cloudsContainer = [[UIView alloc] initWithFrame:self.bounds];
    self.cloudsContainer.userInteractionEnabled = NO;
    self.cloudsContainer.alpha = 0;
    [self.trackView addSubview:self.cloudsContainer];

    self.cloud1 = [self createCloudView];
    self.cloud1.frame = CGRectMake(self.bounds.size.width, 8*_em, 12*_em, 4*_em);
    [self.cloudsContainer addSubview:self.cloud1];

    self.cloud2 = [self createCloudView];
    self.cloud2.frame = CGRectMake(self.bounds.size.width, 16*_em, 12*_em, 4*_em);
    [self.cloudsContainer addSubview:self.cloud2];
}

- (UIView *)createCloudView {
    UIView *cloud = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 12*_em, 4*_em)];
    cloud.backgroundColor = [UIColor whiteColor];
    cloud.layer.cornerRadius = 2 * _em;

    UIView *blob1 = [[UIView alloc] initWithFrame:CGRectMake(1*_em, -4*_em, 5*_em, 5*_em)];
    blob1.layer.cornerRadius = 2.5 * _em;
    blob1.backgroundColor = [UIColor whiteColor];
    [cloud addSubview:blob1];

    UIView *blob2 = [[UIView alloc] initWithFrame:CGRectMake(4*_em, -5*_em, 6*_em, 6*_em)];
    blob2.layer.cornerRadius = 3 * _em;
    blob2.backgroundColor = [UIColor whiteColor];
    [cloud addSubview:blob2];

    return cloud;
}

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

- (void)setOn:(BOOL)on { [self setOn:on animated:NO]; }

- (void)setOn:(BOOL)on animated:(BOOL)animated {
    if (_on == on) return;
    _on = on;

    if (self.changeAction && !_shouldSkipChangeAction && animated) {
        self.changeAction(on, YES);
    }
    BOOL doAnimate = animated && _shouldAnimateImportant;

    if (doAnimate) {
        [UIView animateWithDuration:0.6 delay:0.0 usingSpringWithDamping:0.7 initialSpringVelocity:0.5 options:UIViewAnimationOptionCurveEaseInOut animations:^{
            [self layoutForCurrentStateAnimated:YES];
        } completion:nil];
    } else {
        [self layoutForCurrentStateAnimated:NO];
    }
}

- (void)animateHoverState {
    [UIView animateWithDuration:0.3 animations:^{
        if (self.isHovering) {
            self.knobView.transform = CGAffineTransformMakeScale(0.9, 0.9);
        } else {
            self.knobView.transform = CGAffineTransformIdentity;
            [self layoutForCurrentStateAnimated:NO];
        }
    }];
}

- (void)layoutForCurrentStateAnimated:(BOOL)animated {
    CGFloat knobDia = 23.0 * _em;
    CGFloat margin = 1.0 * _em;

    self.streetBgView.alpha = self.isOn ? 0.0 : 1.0;
    self.skyBgView.alpha = self.isOn ? 1.0 : 0.0;
    self.cloudsContainer.alpha = self.isOn ? 1.0 : 0.0;

    CGFloat runwayTargetX = self.isOn ? (-50.0 * _em) : 0.0;
    self.runwayContainer.transform = CGAffineTransformMakeTranslation(runwayTargetX, 0);

    CGFloat knobTargetX = self.isOn ? (self.bounds.size.width - knobDia - margin) : margin;
    self.knobView.frame = CGRectMake(knobTargetX, margin, knobDia, knobDia);

    UIColor *planeTargetColor = self.isOn ? ColorHex(0x2F8EFC) : ColorHex(0x6B6D76);
    if (animated) {
        [UIView animateWithDuration:0.6 animations:^{
            self.planeIcon.tintColor = planeTargetColor;
        }];
    } else {
        self.planeIcon.tintColor = planeTargetColor;
    }
}

- (CGFloat)knobMargin { return 1.0; }
- (void)blockChangeActionAnimated:(BOOL)animated { _shouldSkipChangeAction = YES; }
- (void)unblockChangeAction { _shouldSkipChangeAction = NO; }

@end
