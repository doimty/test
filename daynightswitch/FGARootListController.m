#import "FGARootListController.h"

#import <Preferences/PSSpecifier.h>
#import <QuartzCore/QuartzCore.h>
#import <notify.h>

static NSString *const DNSPrefsChangedDarwinNotification = @"de.finngaida.daynightswitch/settingschanged";
static NSString *const DNSSwitchStyleKey = @"switchStyle";

@interface FGARootListController ()
@property (nonatomic, strong) NSArray<NSNumber *> *styleValues;
@property (nonatomic, strong) NSArray<NSString *> *styleTitles;
@property (nonatomic, weak) UIControl *styleMenuOverlay;
@property (nonatomic, strong) PSSpecifier *styleSpecifier;
@end

@implementation FGARootListController

- (instancetype)init {
    self = [super init];
    if (self) {
        _styleValues = @[@0, @1, @2, @3, @4];
        _styleTitles = @[@"经典日月", @"清晰条纹", @"动态日月", @"飞机跑道", @"纯洁牙齿"];
    }
    return self;
}

- (NSArray *)specifiers {
    if (!_specifiers) {
        self.styleSpecifier = nil;
        _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
        [self locateStyleSpecifierIfNeeded];
    }

    return _specifiers;
}

- (void)locateStyleSpecifierIfNeeded {
    if (self.styleSpecifier != nil) {
        return;
    }

    for (PSSpecifier *specifier in _specifiers) {
        id key = [specifier.properties objectForKey:@"key"];
        if ([key isKindOfClass:[NSString class]] && [(NSString *)key isEqualToString:DNSSwitchStyleKey]) {
            self.styleSpecifier = specifier;
            break;
        }
    }
}

- (UIColor *)adaptiveColorWithLight:(UIColor *)light dark:(UIColor *)dark {
    if (@available(iOS 13.0, *)) {
        return [UIColor colorWithDynamicProvider:^UIColor * _Nonnull(UITraitCollection * _Nonnull traitCollection) {
            return traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark ? dark : light;
        }];
    }
    return light;
}

- (NSInteger)currentSwitchStyle {
    [self locateStyleSpecifierIfNeeded];
    id value = self.styleSpecifier ? [self readPreferenceValue:self.styleSpecifier] : nil;
    NSInteger style = [value respondsToSelector:@selector(integerValue)] ? [value integerValue] : 0;
    if (style == 8) {
        style = 4;
    }
    for (NSNumber *candidate in self.styleValues) {
        if (candidate.integerValue == style) {
            return style;
        }
    }
    return 0;
}

- (void)writeSwitchStyle:(NSInteger)style {
    [self locateStyleSpecifierIfNeeded];
    if (!self.styleSpecifier) {
        return;
    }
    [self setPreferenceValue:@(style) specifier:self.styleSpecifier];
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    [super setPreferenceValue:value specifier:specifier];
    notify_post([DNSPrefsChangedDarwinNotification UTF8String]);
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [super tableView:tableView cellForRowAtIndexPath:indexPath];
    PSSpecifier *specifier = [self specifierAtIndexPath:indexPath];
    id key = [specifier.properties objectForKey:@"key"];
    if ([key isKindOfClass:[NSString class]] && [(NSString *)key isEqualToString:DNSSwitchStyleKey]) {
        NSInteger current = [self currentSwitchStyle];
        NSUInteger index = [self.styleValues indexOfObject:@(current)];
        cell.detailTextLabel.text = index != NSNotFound ? self.styleTitles[index] : self.styleTitles.firstObject;
        cell.detailTextLabel.textColor = cell.textLabel.textColor;
        cell.accessoryType = UITableViewCellAccessoryNone;
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [self locateStyleSpecifierIfNeeded];
    PSSpecifier *selectedSpecifier = [self specifierAtIndexPath:indexPath];
    if (selectedSpecifier == self.styleSpecifier) {
        UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
        [tableView deselectRowAtIndexPath:indexPath animated:YES];
        if (cell != nil) {
            [self showStyleMenuFromCell:cell];
        }
        return;
    }
    [super tableView:tableView didSelectRowAtIndexPath:indexPath];
}

- (void)showStyleMenuFromCell:(UITableViewCell *)cell {
    [self dismissStyleMenu];

    UIView *hostView = self.view;
    if (hostView == nil) {
        return;
    }

    UIControl *overlay = [[UIControl alloc] initWithFrame:hostView.bounds];
    overlay.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    overlay.backgroundColor = UIColor.clearColor;
    [overlay addTarget:self action:@selector(dismissStyleMenu) forControlEvents:UIControlEventTouchUpInside];

    CGFloat rowHeight = 47.0;
    CGFloat menuWidth = MIN(MAX(cell.bounds.size.width * 0.56, 260.0), hostView.bounds.size.width - 28.0);
    CGFloat menuHeight = rowHeight * self.styleValues.count;
    CGRect anchorFrame = [cell convertRect:cell.bounds toView:hostView];
    CGFloat x = MIN(MAX(CGRectGetMaxX(anchorFrame) - menuWidth - 14.0, 14.0), hostView.bounds.size.width - menuWidth - 14.0);
    CGFloat preferredY = CGRectGetMaxY(anchorFrame) + 8.0;
    CGFloat y = MIN(MAX(preferredY, 12.0), hostView.bounds.size.height - menuHeight - 12.0);

    UIView *menu = [[UIView alloc] initWithFrame:CGRectMake(x, y, menuWidth, menuHeight)];
    menu.backgroundColor = UIColor.clearColor;
    menu.layer.shadowColor = UIColor.blackColor.CGColor;
    menu.layer.shadowOpacity = 0.25;
    menu.layer.shadowRadius = 20.0;
    menu.layer.shadowOffset = CGSizeMake(0, 8);
    menu.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:menu.bounds cornerRadius:14.0].CGPath;

    UIView *contentView = [[UIView alloc] initWithFrame:menu.bounds];
    contentView.backgroundColor = [self adaptiveColorWithLight:[UIColor colorWithWhite:0.98 alpha:0.86]
                                                          dark:[UIColor colorWithWhite:0.12 alpha:0.95]];
    contentView.layer.cornerRadius = 14.0;
    contentView.layer.masksToBounds = YES;
    if (@available(iOS 13.0, *)) {
        contentView.layer.cornerCurve = kCACornerCurveContinuous;
        UIVisualEffectView *blur = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterial]];
        blur.frame = contentView.bounds;
        blur.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [contentView insertSubview:blur atIndex:0];
    }
    [menu addSubview:contentView];

    UIColor *textColor = [self adaptiveColorWithLight:UIColor.blackColor dark:UIColor.whiteColor];
    UIColor *separatorColor = [self adaptiveColorWithLight:[UIColor colorWithWhite:0 alpha:0.10]
                                                      dark:[UIColor colorWithWhite:1.0 alpha:0.12]];
    UIColor *checkmarkColor = [self adaptiveColorWithLight:[UIColor colorWithRed:0.0 green:0.36 blue:1.0 alpha:1.0]
                                                      dark:[UIColor colorWithRed:0.4 green:0.7 blue:1.0 alpha:1.0]];
    NSInteger current = [self currentSwitchStyle];

    for (NSUInteger index = 0; index < self.styleTitles.count; index++) {
        UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
        button.tag = index;
        button.frame = CGRectMake(0, rowHeight * index, menuWidth, rowHeight);
        button.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
        button.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightRegular];
        [button setTitle:self.styleTitles[index] forState:UIControlStateNormal];
        [button setTitleColor:textColor forState:UIControlStateNormal];
        button.titleEdgeInsets = UIEdgeInsetsMake(0, 18, 0, 48);
        [button addTarget:self action:@selector(styleMenuItemTapped:) forControlEvents:UIControlEventTouchUpInside];
        [contentView addSubview:button];

        if (self.styleValues[index].integerValue == current) {
            UILabel *checkmark = [[UILabel alloc] initWithFrame:CGRectMake(menuWidth - 39, rowHeight * index, 22, rowHeight)];
            checkmark.text = @"✓";
            checkmark.textAlignment = NSTextAlignmentCenter;
            checkmark.textColor = checkmarkColor;
            checkmark.font = [UIFont systemFontOfSize:19 weight:UIFontWeightSemibold];
            [contentView addSubview:checkmark];
        }

        if (index < self.styleTitles.count - 1) {
            UIView *separator = [[UIView alloc] initWithFrame:CGRectMake(0, rowHeight * (index + 1) - 0.5, menuWidth, 0.5)];
            separator.backgroundColor = separatorColor;
            [contentView addSubview:separator];
        }
    }

    [overlay addSubview:menu];
    [hostView addSubview:overlay];
    self.styleMenuOverlay = overlay;

    menu.alpha = 0.0;
    menu.transform = CGAffineTransformMakeScale(0.96, 0.96);
    [UIView animateWithDuration:0.16 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
        menu.alpha = 1.0;
        menu.transform = CGAffineTransformIdentity;
    } completion:nil];
}

- (void)styleMenuItemTapped:(UIButton *)sender {
    if (sender.tag < 0 || sender.tag >= (NSInteger)self.styleValues.count) {
        return;
    }
    NSInteger selectedStyle = self.styleValues[sender.tag].integerValue;
    [self writeSwitchStyle:selectedStyle];
    [self dismissStyleMenu];
    self.styleSpecifier = nil;
    [self reloadSpecifiers];
}

- (void)dismissStyleMenu {
    UIControl *overlay = self.styleMenuOverlay;
    if (!overlay) {
        return;
    }
    self.styleMenuOverlay = nil;
    [UIView animateWithDuration:0.12 animations:^{
        overlay.alpha = 0.0;
    } completion:^(__unused BOOL finished) {
        [overlay removeFromSuperview];
    }];
}

- (void)twitter {
    UIApplication *app = [UIApplication sharedApplication];
    if ([app canOpenURL:[NSURL URLWithString:@"twitter://fga"]]) {
        [app openURL:[NSURL URLWithString:@"twitter://user?screen_name=fga"] options:@{} completionHandler:nil];
    } else if ([app canOpenURL:[NSURL URLWithString:@"tweetbot://fga/user_profile/fga"]]) {
        [app openURL:[NSURL URLWithString:@"tweetbot://fga/user_profile/fga"] options:@{} completionHandler:nil];
    } else if ([app canOpenURL:[NSURL URLWithString:@"https://twitter.com/fga"]]) {
        [app openURL:[NSURL URLWithString:@"https://twitter.com/fga"] options:@{} completionHandler:nil];
    }
}

- (void)github {
    [self openURL:[NSURL URLWithString:@"https://github.com/finngaida"]];
}

- (void)mail {
    [self openURL:[NSURL URLWithString:@"mailto:f@fga.pw?subject=DayNightSwitch%20Feature%20Request"]];
}

- (void)paypal {
    [self openURL:[NSURL URLWithString:@"https://paypal.me/fga"]];
}

- (void)support {
    [self openURL:[NSURL URLWithString:@"https://havoc.app/search/82Flex"]];
}

- (void)openURL:(NSURL *)url {
    [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
}

@end
