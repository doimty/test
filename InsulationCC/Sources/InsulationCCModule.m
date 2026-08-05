#import <UIKit/UIKit.h>
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

static UIColor *InsulationColorForPowerMode(NSString *mode) {
    if ([mode isEqualToString:@"fullPower"]) {
        return [UIColor systemRedColor];
    }
    if ([mode isEqualToString:@"lowPower"]) {
        return [UIColor systemOrangeColor];
    }
    return [UIColor whiteColor];
}

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
        menuViews = nil;
    }
    if ([menuViews isKindOfClass:[NSArray class]] && [menuViews count] != 0) {
        return menuViews;
    }

    id container = nil;
    @try {
        container = [self valueForKey:@"_menuItemsContainer"];
    } @catch (__unused NSException *exception) {
        container = nil;
    }
    if ([container isKindOfClass:[UIStackView class]]) {
        return ((UIStackView *)container).arrangedSubviews;
    }
    return nil;
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

- (void)syncMenuSelectionViews:(NSArray *)menuViews {
    NSString *selectedMode = nil;
    if (self.selectedIndex >= 0 && self.selectedIndex < (NSInteger)self.modeValues.count) {
        selectedMode = self.modeValues[(NSUInteger)self.selectedIndex];
    }

    NSUInteger itemIndex = 0;
    for (id candidate in menuViews) {
        if (![candidate isKindOfClass:[CCUIMenuModuleItemView class]]) {
            continue;
        }

        CCUIMenuModuleItemView *itemView = candidate;
        CCUIMenuModuleItem *item = itemView.menuItem;
        NSString *identifier = nil;
        if ([item respondsToSelector:@selector(identifier)]) {
            id value = item.identifier;
            if ([value isKindOfClass:[NSString class]]) {
                identifier = value;
            }
        }
        BOOL selected = identifier ? [identifier isEqualToString:selectedMode] : itemIndex == (NSUInteger)self.selectedIndex;
        itemIndex++;

        if ([item respondsToSelector:@selector(setSelected:)]) {
            item.selected = selected;
        }
        if (!selected) {
            itemView.trailingView = nil;
        }
    }
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
    [self syncMenuSelectionViews:[self menuItemViewsIfAvailable]];
    if ([self respondsToSelector:@selector(_updateLeadingAndTrailingViews)]) {
        [self _updateLeadingAndTrailingViews];
    }
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
    [self syncMenuSelectionViews:[self menuItemViewsIfAvailable]];
    if ([self respondsToSelector:@selector(_updateLeadingAndTrailingViews)]) {
        [self _updateLeadingAndTrailingViews];
    }
}

- (void)_handleActionTapped:(CCUIMenuModuleItemView *)view {
    UIStackView *visibleMenuStack = [view.superview isKindOfClass:[UIStackView class]] ? (UIStackView *)view.superview : nil;
    NSArray *visibleMenuViews = visibleMenuStack ? [visibleMenuStack.arrangedSubviews copy] : [[self menuItemViewsIfAvailable] copy];
    NSString *mode = [self modeForMenuItemView:view];
    if (!mode) {
        [super _handleActionTapped:view];
        return;
    }

    InsulationSetPowerMode(mode);
    [self refreshSelectionState];

    [super _handleActionTapped:view];
    if (visibleMenuViews.count == 0) {
        visibleMenuViews = [[self menuItemViewsIfAvailable] copy];
    }
    [self syncMenuSelectionViews:visibleMenuViews];
    if ([self respondsToSelector:@selector(_updateLeadingAndTrailingViews)]) {
        [self _updateLeadingAndTrailingViews];
    }
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
