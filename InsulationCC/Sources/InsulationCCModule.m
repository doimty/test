#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <notify.h>

#import "ControlCenterUIKit/CCUIContentModule.h"
#import "ControlCenterUIKit/CCUIButtonModuleView.h"
#import "ControlCenterUIKit/CCUIMenuModuleItem.h"
#import "ControlCenterUIKit/CCUIMenuModuleItemView.h"
#import "ControlCenterUIKit/CCUIMenuModuleViewController.h"
#import "InsulationPrefs.h"

static NSString *const InsulationPrefsPath = @"/var/mobile/Library/Preferences/com.be-huge.insulation-prefs.plist";
static NSString *const InsulationPowerModeKey = @"thermalPowerMode";
static NSString *const InsulationExecuteNotification = @"com.be-huge.insulation-executePuppetEvent";
static NSString *const InsulationRestartNotification = @"com.be-huge.insulation-restartThermalMonitor";
static const char *InsulationRuntimeStateName = "com.be-huge.insulation.runtimeState";
static const uint64_t InsulationRuntimeStateMagic = 0x494E535500000000ULL;
static const CGFloat InsulationModeDotDiameter = 9.0;

static UIColor *InsulationColorForPowerMode(NSString *mode) {
    if ([mode isEqualToString:@"fullPower"]) {
        return [UIColor systemRedColor];
    }
    if ([mode isEqualToString:@"lowPower"]) {
        return [UIColor systemYellowColor];
    }
    return [UIColor whiteColor];
}

@interface InsulationModeDotView : UIView
@property (nonatomic, copy, readonly) NSString *mode;
- (instancetype)initWithMode:(NSString *)mode;
@end

@implementation InsulationModeDotView

- (instancetype)initWithMode:(NSString *)mode {
    self = [super initWithFrame:CGRectMake(0, 0, InsulationModeDotDiameter, InsulationModeDotDiameter)];
    if (self) {
        _mode = [mode copy];
        self.backgroundColor = InsulationColorForPowerMode(mode);
        self.userInteractionEnabled = NO;
        self.layer.cornerRadius = InsulationModeDotDiameter / 2.0;
        self.layer.masksToBounds = YES;
    }
    return self;
}

- (CGSize)intrinsicContentSize {
    return CGSizeMake(InsulationModeDotDiameter, InsulationModeDotDiameter);
}

- (CGSize)sizeThatFits:(__unused CGSize)size {
    return CGSizeMake(InsulationModeDotDiameter, InsulationModeDotDiameter);
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat side = MIN(CGRectGetWidth(self.bounds), CGRectGetHeight(self.bounds));
    self.layer.cornerRadius = side / 2.0;
}

@end

static void InsulationPostDarwinNotification(NSString *name) {
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge CFStringRef)name, NULL, NULL, true);
}

static void InsulationPostRuntimeState(void) {
    int token = 0;
    if (notify_register_check(InsulationRuntimeStateName, &token) != NOTIFY_STATUS_OK) {
        return;
    }
    notify_set_state(token, InsulationRuntimeStateMagic);
    notify_post(InsulationRuntimeStateName);
    notify_cancel(token);
}

static NSString *InsulationResolvedPrefsPath(void) {
    return rootlessPath(InsulationPrefsPath);
}

static NSString *InsulationCurrentPowerMode(void) {
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:InsulationResolvedPrefsPath()];
    id value = [prefs objectForKey:InsulationPowerModeKey];
    if (![value isKindOfClass:[NSString class]]) {
        return @"off";
    }
    NSString *mode = value;
    if ([mode isEqualToString:@"lowPower"] || [mode isEqualToString:@"fullPower"]) {
        return mode;
    }
    return @"off";
}

static void InsulationSetPowerMode(NSString *mode) {
    NSMutableDictionary *prefs = [NSMutableDictionary dictionaryWithContentsOfFile:InsulationResolvedPrefsPath()];
    if (!prefs) {
        prefs = [NSMutableDictionary dictionary];
    }
    [prefs setObject:mode forKey:InsulationPowerModeKey];
    [prefs writeToFile:InsulationResolvedPrefsPath() atomically:YES];
    InsulationPostRuntimeState();
    InsulationPostDarwinNotification(InsulationExecuteNotification);
    InsulationPostDarwinNotification(InsulationRestartNotification);
}

@interface InsulationCCModuleViewController : CCUIMenuModuleViewController
@property (nonatomic, copy) NSArray<NSString *> *modeValues;
@property (nonatomic, copy) NSArray<NSString *> *modeTitles;
@property (nonatomic, copy) NSArray<NSString *> *modeSubtitles;
@property (nonatomic, assign) NSInteger selectedIndex;
@property (nonatomic, assign) BOOL applyingModeDots;
@end

@implementation InsulationCCModuleViewController

- (void)forceWhiteHeaderTitle {
    id titleLabel = nil;
    @try {
        titleLabel = [self valueForKey:@"_titleLabel"];
    } @catch (__unused NSException *exception) {
        titleLabel = nil;
    }
    if ([titleLabel isKindOfClass:[UILabel class]]) {
        ((UILabel *)titleLabel).textColor = [UIColor whiteColor];
    }
}

- (instancetype)init {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _modeValues = @[@"off", @"lowPower", @"fullPower"];
        _modeTitles = @[@"原生态", @"低电量", @"满频率"];
        _modeSubtitles = @[@"苹果原生温控", @"模拟低电频率", @"防止温控降频"];
        _selectedIndex = 0;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    UIImage *glyph = nil;
    if (@available(iOS 13.0, *)) {
        UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:28 weight:UIImageSymbolWeightMedium];
        glyph = [UIImage systemImageNamed:@"waveform.path.ecg" withConfiguration:config];
    }
    if (!glyph) {
        UIGraphicsBeginImageContextWithOptions(CGSizeMake(42, 42), NO, 0);
        UIBezierPath *path = [UIBezierPath bezierPath];
        [path moveToPoint:CGPointMake(4, 23)];
        [path addLineToPoint:CGPointMake(14, 23)];
        [path addLineToPoint:CGPointMake(19, 10)];
        [path addLineToPoint:CGPointMake(25, 34)];
        [path addLineToPoint:CGPointMake(30, 20)];
        [path addLineToPoint:CGPointMake(38, 20)];
        [[UIColor whiteColor] setStroke];
        path.lineWidth = 3;
        [path stroke];
        glyph = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
    }

    self.glyphImage = glyph;
    self.indentation = 2;
    self.title = @"Insulation";
    self.useTrailingCheckmarkLayout = YES;
    self.shouldProvideOwnPlatter = YES;
    [self forceWhiteHeaderTitle];
}

- (void)controlCenterWillPresent {
    [self refreshSelectionState];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self refreshSelectionState];
    [self forceWhiteHeaderTitle];
}

- (BOOL)shouldBeginTransitionToExpandedContentModule {
    return YES;
}

- (void)willTransitionToExpandedContentMode:(BOOL)animated {
    [super willTransitionToExpandedContentMode:animated];
    [self rebuildMenuItems];
    [self forceWhiteHeaderTitle];
}

- (void)refreshSelectionState {
    NSString *current = InsulationCurrentPowerMode();
    NSUInteger found = [self.modeValues indexOfObject:current];
    self.selectedIndex = found == NSNotFound ? 0 : (NSInteger)found;

    UIColor *glyphColor = InsulationColorForPowerMode(current);
    BOOL active = self.selectedIndex != 0;
    self.selectedGlyphColor = glyphColor;
    self.glyphState = active ? @"on" : @"off";
    self.selected = active;

    if (!self.viewLoaded) {
        return;
    }

    CCUIButtonModuleView *buttonView = self.buttonView;
    if (![buttonView isKindOfClass:[CCUIButtonModuleView class]]) {
        return;
    }
    buttonView.selectedGlyphColor = glyphColor;
    if ([buttonView respondsToSelector:@selector(_updateForStateChange)]) {
        [buttonView _updateForStateChange];
    }
}

- (NSArray *)menuItemViewsIfAvailable {
    id menuViews = nil;
    @try {
        menuViews = [self valueForKey:@"_menuItemsViews"];
    } @catch (__unused NSException *exception) {
        return nil;
    }
    return [menuViews isKindOfClass:[NSArray class]] ? menuViews : nil;
}

- (NSString *)modeForMenuItemView:(CCUIMenuModuleItemView *)view {
    if (![view isKindOfClass:[CCUIMenuModuleItemView class]]) {
        return nil;
    }

    id item = view.menuItem;
    if ([item isKindOfClass:[CCUIMenuModuleItem class]]) {
        NSString *identifier = ((CCUIMenuModuleItem *)item).identifier;
        if ([identifier isKindOfClass:[NSString class]] && [self.modeValues containsObject:identifier]) {
            return identifier;
        }
    }

    NSArray *menuViews = [self menuItemViewsIfAvailable];
    NSUInteger idx = menuViews ? [menuViews indexOfObjectIdenticalTo:view] : NSNotFound;
    if (idx == NSNotFound && [view.superview isKindOfClass:[UIStackView class]]) {
        idx = [((UIStackView *)view.superview).arrangedSubviews indexOfObjectIdenticalTo:view];
    }
    if (idx == NSNotFound || idx >= self.modeValues.count) {
        return nil;
    }
    return self.modeValues[idx];
}

- (void)updateMenuSelectionViews:(NSArray *)menuViews {
    if (self.applyingModeDots) {
        return;
    }
    self.applyingModeDots = YES;

    for (NSUInteger i = 0; i < menuViews.count; i++) {
        id candidate = menuViews[i];
        if (![candidate isKindOfClass:[CCUIMenuModuleItemView class]]) {
            continue;
        }

        CCUIMenuModuleItemView *itemView = candidate;
        BOOL selected = (i < self.modeValues.count && (NSInteger)i == self.selectedIndex);

        id item = itemView.menuItem;
        if ([item isKindOfClass:[CCUIMenuModuleItem class]] && ((CCUIMenuModuleItem *)item).selected != selected) {
            ((CCUIMenuModuleItem *)item).selected = selected;
        }
        if (itemView.leadingView) {
            itemView.leadingView = nil;
        }

        if (!selected) {
            if (itemView.trailingView) {
                itemView.trailingView = nil;
            }
            continue;
        }

        NSString *mode = self.modeValues[i];
        UIView *existing = itemView.trailingView;
        if ([existing isKindOfClass:[InsulationModeDotView class]] &&
            [((InsulationModeDotView *)existing).mode isEqualToString:mode]) {
            continue;
        }
        itemView.trailingView = [[InsulationModeDotView alloc] initWithMode:mode];
    }

    self.applyingModeDots = NO;
}

- (void)applyModeDots {
    NSArray *menuViews = [self menuItemViewsIfAvailable];
    if (menuViews) {
        [self updateMenuSelectionViews:menuViews];
    }
}

- (void)_updateLeadingAndTrailingViews {
    [super _updateLeadingAndTrailingViews];
    [self applyModeDots];
}

- (void)rebuildMenuItems {
    [self refreshSelectionState];
    NSMutableArray<CCUIMenuModuleItem *> *items = [NSMutableArray arrayWithCapacity:self.modeValues.count];
    for (NSUInteger i = 0; i < self.modeValues.count; i++) {
        NSString *title = self.modeTitles[i];
        NSString *mode = self.modeValues[i];
        CCUIMenuModuleItem *item = [[CCUIMenuModuleItem alloc] initWithTitle:title identifier:mode handler:nil];
        item.subtitle = self.modeSubtitles[i];
        item.selected = ((NSInteger)i == self.selectedIndex);
        [items addObject:item];
    }
    self.menuItems = items;
    [self applyModeDots];
}

- (void)buttonTapped:(CCUIButtonModuleView *)button forEvent:(UIEvent *)event {
    NSUInteger count = self.modeValues.count;
    if (count == 0) {
        [super buttonTapped:button forEvent:event];
        return;
    }

    NSUInteger found = [self.modeValues indexOfObject:InsulationCurrentPowerMode()];
    NSUInteger idx = found == NSNotFound ? 0 : found;
    InsulationSetPowerMode(self.modeValues[(idx + 1) % count]);
    [self refreshSelectionState];

    [super buttonTapped:button forEvent:event];
    [self applyModeDots];
}

- (void)_handleActionTapped:(CCUIMenuModuleItemView *)view {
    NSString *mode = [self modeForMenuItemView:view];
    if (!mode) {
        [super _handleActionTapped:view];
        return;
    }

    InsulationSetPowerMode(mode);
    [self refreshSelectionState];

    [super _handleActionTapped:view];
    [self applyModeDots];
}

- (BOOL)_canShowWhileLocked {
    return YES;
}

@end

@interface InsulationCCModule : NSObject <CCUIContentModule>
@property (nonatomic, strong, readonly) UIViewController<CCUIContentModuleContentViewController> *contentViewController;
@property (nonatomic, strong, readonly) UIViewController *backgroundViewController;
@end

@implementation InsulationCCModule
@synthesize backgroundViewController;

- (instancetype)init {
    self = [super init];
    if (self) {
        _contentViewController = [[InsulationCCModuleViewController alloc] init];
    }
    return self;
}

@end
