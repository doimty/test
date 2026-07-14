#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>

#import "ControlCenterUIKit/CCUIContentModule.h"
#import "ControlCenterUIKit/CCUIButtonModuleView.h"
#import "ControlCenterUIKit/CCUIMenuModuleItem.h"
#import "ControlCenterUIKit/CCUIMenuModuleItemView.h"
#import "ControlCenterUIKit/CCUIMenuModuleViewController.h"
#import "InsulationPrefs.h"

static NSString *const InsulationPrefsPath = @"/var/mobile/Library/Preferences/com.be-huge.insulation-prefs.plist";
static NSString *const InsulationPowerModeKey = @"thermalPowerMode";
static NSString *const InsulationModeChangeNotification = @"com.be-huge.insulation-modeDidChange";

static void InsulationPostDarwinNotification(NSString *name) {
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge CFStringRef)name, NULL, NULL, true);
}

static NSString *InsulationResolvedPrefsPath(void) {
    return rootlessPath(InsulationPrefsPath);
}

static NSString *InsulationCurrentPowerMode(void) {
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:InsulationResolvedPrefsPath()];
    NSString *mode = [prefs objectForKey:InsulationPowerModeKey];
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
    InsulationPostDarwinNotification(InsulationModeChangeNotification);
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
    self.selectedGlyphColor = [UIColor systemOrangeColor];
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
    NSInteger idx = [self.modeValues indexOfObject:current];
    self.selectedIndex = idx == NSNotFound ? 0 : idx;
    self.selected = self.selectedIndex != 0;
    self.glyphState = self.selected ? @"on" : @"off";
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
}

- (void)buttonTapped:(CCUIButtonModuleView *)button forEvent:(UIEvent *)event {
    NSString *current = InsulationCurrentPowerMode();
    NSInteger idx = [self.modeValues indexOfObject:current];
    if (idx == NSNotFound) {
        idx = 0;
    }
    NSInteger nextIdx = (idx + 1) % self.modeValues.count;
    InsulationSetPowerMode(self.modeValues[nextIdx]);
    [self refreshSelectionState];
    [super buttonTapped:button forEvent:event];
}

- (void)_handleActionTapped:(CCUIMenuModuleItemView *)view {
    [super _handleActionTapped:view];

    NSArray<CCUIMenuModuleItemView *> *menuViews = ((UIStackView *)view.superview).arrangedSubviews;
    if (self.selectedIndex >= 0 && self.selectedIndex < (NSInteger)menuViews.count) {
        CCUIMenuModuleItemView *lastView = menuViews[self.selectedIndex];
        lastView.menuItem.selected = NO;
        if (self.useTrailingCheckmarkLayout) {
            lastView.trailingView = nil;
        } else {
            lastView.leadingView = nil;
        }
    }

    NSInteger tappedIndex = [menuViews indexOfObject:view];
    if (tappedIndex == NSNotFound || tappedIndex >= (NSInteger)self.modeValues.count) {
        return;
    }

    InsulationSetPowerMode(self.modeValues[tappedIndex]);

    view.menuItem.selected = YES;
    [self _updateLeadingAndTrailingViews];

    self.selectedIndex = tappedIndex;
    self.selected = tappedIndex != 0;
    self.glyphState = self.selected ? @"on" : @"off";
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
