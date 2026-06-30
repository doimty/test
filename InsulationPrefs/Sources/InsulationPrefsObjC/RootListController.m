#import "RootListController.h"

#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <Preferences/PSSpecifier.h>

#import "InsulationPrefsNotificationHelper.h"
#import "InsulationPrefsParams.h"

@interface RootListController ()
@property (nonatomic, weak) UIControl *cpuModeMenuOverlay;
@end

static NSArray<NSString *> *InsulationPrefsCPUModeValues(void) {
    return @[@"off", @"lowPower", @"fullPower"];
}

static NSArray<NSString *> *InsulationPrefsCPUModeTitles(void) {
    return @[@"苹果原生温控", @"模拟低电频率", @"防止温控降频"];
}

static BOOL InsulationPrefsSupportsIOS13(void) {
    NSOperatingSystemVersion version = {13, 0, 0};
    return [[NSProcessInfo processInfo] isOperatingSystemAtLeastVersion:version];
}

static CALayerCornerCurve InsulationPrefsContinuousCornerCurve(void) {
    return (CALayerCornerCurve)@"continuous"; // kCACornerCurveContinuous
}

static UIBlurEffectStyle InsulationPrefsSystemThinMaterialBlurStyle(void) {
    return (UIBlurEffectStyle)6; // UIBlurEffectStyleSystemThinMaterial
}

static void InsulationPrefsSetContinuousCornerCurveIfAvailable(CALayer *layer) {
    SEL setter = @selector(setCornerCurve:);
    if ([layer respondsToSelector:setter]) {
        void (*setCornerCurve)(id, SEL, CALayerCornerCurve) = (void (*)(id, SEL, CALayerCornerCurve))[layer methodForSelector:setter];
        setCornerCurve(layer, setter, InsulationPrefsContinuousCornerCurve());
    }
}

@implementation RootListController

- (NSMutableArray *)specifiers {
    NSMutableArray *specifiers = [self valueForKey:@"_specifiers"];
    if (specifiers) {
        return specifiers;
    }
    specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    [self setValue:specifiers forKey:@"_specifiers"];
    return specifiers;
}

- (id)readPreferenceValue:(PSSpecifier *)specifier {
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:InsulationPrefsPlistPath()];
    id key = [specifier.properties objectForKey:@"key"];
    id defaultValue = [specifier.properties objectForKey:@"default"];
    id value = key ? [prefs objectForKey:key] : nil;
    return value ?: defaultValue;
}

- (NSString *)currentCPUMode {
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:InsulationPrefsPlistPath()];
    NSString *mode = [prefs objectForKey:InsulationPrefsPowerModeKey];
    return [InsulationPrefsCPUModeValues() containsObject:mode] ? mode : @"off";
}

- (UIColor *)adaptiveColorWithLight:(UIColor *)light dark:(UIColor *)dark {
    if (InsulationPrefsSupportsIOS13()) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunguarded-availability-new"
        UIColor *color = [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traitCollection) {
            return traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark ? dark : light;
        }];
#pragma clang diagnostic pop
        return color;
    }
    return light;
}

- (void)insulation_writePreferenceValue:(id)value forKey:(NSString *)key {
    NSMutableDictionary *prefs = [NSMutableDictionary dictionaryWithContentsOfFile:InsulationPrefsPlistPath()];
    if (!prefs) {
        prefs = [NSMutableDictionary dictionary];
    }
    if (value) {
        [prefs setObject:value forKey:key];
    } else {
        [prefs removeObjectForKey:key];
    }
    [prefs writeToFile:InsulationPrefsPlistPath() atomically:YES];

    if ([key hasPrefix:@"thermal"]) {
        InsulationPrefsPostApplyNotifications();
    }
    if ([key isEqualToString:InsulationPrefsPowerModeKey]) {
        InsulationPrefsPostRestartNotifications();
    }
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *key = [specifier.properties objectForKey:@"key"];
    if (![key isKindOfClass:[NSString class]]) {
        return;
    }
    [self insulation_writePreferenceValue:value forKey:key];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
    if ([cell.textLabel.text isEqualToString:@"CPU 模式"]) {
        [tableView deselectRowAtIndexPath:indexPath animated:YES];
        [self showCPUModeMenuFromCell:cell];
        return;
    }
    [super tableView:tableView didSelectRowAtIndexPath:indexPath];
}

- (void)showCPUModeMenuFromCell:(UITableViewCell *)cell {
    [self dismissCPUModeMenu];

    UIView *hostView = self.view;
    if (!hostView) {
        return;
    }

    UIControl *overlay = [[UIControl alloc] initWithFrame:hostView.bounds];
    overlay.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    overlay.backgroundColor = [UIColor clearColor];
    [overlay addTarget:self action:@selector(dismissCPUModeMenu) forControlEvents:UIControlEventTouchUpInside];

    CGFloat rowHeight = 47.0;
    CGFloat menuWidth = MIN(MAX(cell.bounds.size.width * 0.56, 260.0), hostView.bounds.size.width - 28.0);
    CGFloat menuHeight = rowHeight * InsulationPrefsCPUModeValues().count;
    CGRect anchorFrame = [cell convertRect:cell.bounds toView:hostView];
    CGFloat x = MIN(MAX(CGRectGetMaxX(anchorFrame) - menuWidth - 14.0, 14.0), hostView.bounds.size.width - menuWidth - 14.0);
    CGFloat preferredY = CGRectGetMaxY(anchorFrame) + 8.0;
    CGFloat y = MIN(MAX(preferredY, 12.0), hostView.bounds.size.height - menuHeight - 12.0);

    UIView *menu = [[UIView alloc] initWithFrame:CGRectMake(x, y, menuWidth, menuHeight)];
    menu.backgroundColor = [UIColor clearColor];
    menu.layer.shadowColor = [UIColor blackColor].CGColor;
    menu.layer.shadowOpacity = 0.25;
    menu.layer.shadowRadius = 20.0;
    menu.layer.shadowOffset = CGSizeMake(0, 8);
    menu.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:menu.bounds cornerRadius:14.0].CGPath;

    UIView *contentView = [[UIView alloc] initWithFrame:menu.bounds];
    contentView.backgroundColor = [self adaptiveColorWithLight:[UIColor colorWithWhite:0.98 alpha:0.86]
                                                          dark:[UIColor colorWithWhite:0.12 alpha:0.95]];
    contentView.layer.cornerRadius = 14.0;
    contentView.layer.masksToBounds = YES;
    if (InsulationPrefsSupportsIOS13()) {
        InsulationPrefsSetContinuousCornerCurveIfAvailable(contentView.layer);
        UIVisualEffectView *blur = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:InsulationPrefsSystemThinMaterialBlurStyle()]];
        blur.frame = contentView.bounds;
        blur.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [contentView insertSubview:blur atIndex:0];
    }
    [menu addSubview:contentView];

    UIColor *textColor = [self adaptiveColorWithLight:[UIColor blackColor] dark:[UIColor whiteColor]];
    UIColor *separatorColor = [self adaptiveColorWithLight:[UIColor colorWithWhite:0 alpha:0.10] dark:[UIColor colorWithWhite:1.0 alpha:0.12]];
    UIColor *checkmarkColor = [self adaptiveColorWithLight:[UIColor colorWithRed:0.0 green:0.36 blue:1.0 alpha:1.0]
                                                       dark:[UIColor colorWithRed:0.4 green:0.7 blue:1.0 alpha:1.0]];
    NSString *current = [self currentCPUMode];
    NSArray<NSString *> *titles = InsulationPrefsCPUModeTitles();
    NSArray<NSString *> *values = InsulationPrefsCPUModeValues();
    for (NSUInteger index = 0; index < titles.count; index++) {
        UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
        button.tag = (NSInteger)index;
        button.frame = CGRectMake(0, index * rowHeight, menuWidth, rowHeight);
        button.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
        button.accessibilityLabel = titles[index];
        [button addTarget:self action:@selector(cpuModeMenuItemTapped:) forControlEvents:UIControlEventTouchUpInside];
        [contentView addSubview:button];

        UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(18, index * rowHeight, menuWidth - 66, rowHeight)];
        titleLabel.text = titles[index];
        titleLabel.textColor = textColor;
        titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightRegular];
        titleLabel.userInteractionEnabled = NO;
        [contentView addSubview:titleLabel];

        if ([values[index] isEqualToString:current]) {
            UILabel *checkmark = [[UILabel alloc] initWithFrame:CGRectMake(menuWidth - 39, index * rowHeight, 22, rowHeight)];
            checkmark.text = @"✓";
            checkmark.textAlignment = NSTextAlignmentCenter;
            checkmark.textColor = checkmarkColor;
            checkmark.font = [UIFont systemFontOfSize:19 weight:UIFontWeightSemibold];
            [contentView addSubview:checkmark];
        }

        if (index < titles.count - 1) {
            UIView *separator = [[UIView alloc] initWithFrame:CGRectMake(0, (index + 1) * rowHeight - 0.5, menuWidth, 0.5)];
            separator.backgroundColor = separatorColor;
            [contentView addSubview:separator];
        }
    }

    [overlay addSubview:menu];
    [hostView addSubview:overlay];
    self.cpuModeMenuOverlay = overlay;

    menu.alpha = 0;
    menu.transform = CGAffineTransformMakeScale(0.96, 0.96);
    [UIView animateWithDuration:0.16 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
        menu.alpha = 1;
        menu.transform = CGAffineTransformIdentity;
    } completion:nil];
}

- (void)cpuModeMenuItemTapped:(UIButton *)sender {
    NSArray<NSString *> *values = InsulationPrefsCPUModeValues();
    if (sender.tag < 0 || sender.tag >= (NSInteger)values.count) {
        return;
    }
    NSString *selectedValue = values[(NSUInteger)sender.tag];
    [self insulation_writePreferenceValue:selectedValue forKey:InsulationPrefsPowerModeKey];
    [self dismissCPUModeMenu];
    [self reloadSpecifiers];
}

- (void)dismissCPUModeMenu {
    UIControl *overlay = self.cpuModeMenuOverlay;
    if (!overlay) {
        return;
    }
    self.cpuModeMenuOverlay = nil;
    [UIView animateWithDuration:0.12 animations:^{
        overlay.alpha = 0;
    } completion:^(__unused BOOL finished) {
        [overlay removeFromSuperview];
    }];
}

@end
