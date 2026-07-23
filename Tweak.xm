#import <objc/runtime.h>
#import <CoreFoundation/CoreFoundation.h>
#import "DayNightSwitch.h"
#import "StripedSwitch.h"
#import "DongRiYueSwitch.h"
#import "PlaneSwitch.h"
#import "TeethSwitch.h"


@interface PSSwitchTableCell : UITableViewCell
- (SEL)cellAction;
- (id)specifier;
- (id)control;
@end

@interface PSSpecifier : NSObject
- (NSString *)identifier;
@end

static char DNSDayNightSwitchKey;
static char DNSCurrentStyleKey;
static char DNSOriginalTintColorKey;
static char DNSOriginalOnTintColorKey;
static char DNSOriginalThumbTintColorKey;
static char DNSAppearanceCapturedKey;
static char DNSOriginalShadowOpacityKey;
static NSString *const DNSPrefsChangedNotification = @"DNSPrefsChangedNotification";

// ================= 【核心：通用开关协议，保证系统不崩溃】 =================
@protocol FGASwitchProtocol <NSObject>
@property (nonatomic, assign, getter=isOn) BOOL on;
@property (nonatomic, copy, nullable) void (^changeAction)(BOOL, BOOL);
- (void)blockChangeActionAnimated:(BOOL)animated;
- (void)unblockChangeAction;
- (void)setOn:(BOOL)on;
@end
// =======================================================================

// MARK: Settings
static BOOL global = NO;
static NSInteger switchStyle = 0; // 新增：保存用户选择的样式
static NSString *const DNSPrefsMobilePath = @"/var/mobile/Library/Preferences/de.finngaida.daynightswitch.plist";
static NSString *const DNSPrefsRootlessPath = @"/var/jb/var/mobile/Library/Preferences/de.finngaida.daynightswitch.plist";

// ========== DIAGNOSTIC ==========
// Remove before release.
static NSString *const DNSDiagPath = @"/var/mobile/Library/Preferences/de.finngaida.daynightswitch.diag.plist";
static void DNSDiag(NSString *event, NSDictionary *extra) {
    NSString *bundleId = [[NSBundle mainBundle] bundleIdentifier] ?: @"unknown";
    NSMutableDictionary *entry = [NSMutableDictionary dictionary];
    entry[@"t"] = @([[NSDate date] timeIntervalSince1970]);
    entry[@"p"] = bundleId;
    entry[@"e"] = event;
    entry[@"g"] = @(global);
    entry[@"s"] = @(switchStyle);
    if (extra) [entry addEntriesFromDictionary:extra];
    @synchronized ([NSObject class]) {
        NSMutableArray *arr = [NSMutableArray arrayWithContentsOfFile:DNSDiagPath];
        if (!arr) arr = [NSMutableArray array];
        if (arr.count > 200) [arr removeObjectsInRange:NSMakeRange(0, arr.count - 150)];
        [arr addObject:entry];
        [arr writeToFile:DNSDiagPath atomically:YES];
    }
}
// ================================

// Injected third-party processes must read the shared preference file directly.
// Their CFPreferences cache for another app domain can be stale or empty.
static NSString *DNSPrefsPath(void) {
    NSFileManager *fm = [NSFileManager defaultManager];
    if ([fm fileExistsAtPath:DNSPrefsMobilePath]) {
        return DNSPrefsMobilePath;
    }
    if ([fm fileExistsAtPath:DNSPrefsRootlessPath]) {
        return DNSPrefsRootlessPath;
    }
    return DNSPrefsMobilePath;
}

static NSInteger DNSMigrateSwitchStyle(NSInteger style) {
    // Style 8 was the pre-1.2.2 value for TeethSwitch.
    return style == 8 ? 4 : style;
}

static BOOL DNSIsValidSwitchStyle(NSInteger style) {
    return style >= 0 && style <= 4;
}

static void DNSReadPrefs(void) {
    CFPreferencesAppSynchronize(CFSTR("de.finngaida.daynightswitch"));
    NSMutableDictionary *settings = [[NSMutableDictionary alloc] initWithContentsOfFile:DNSPrefsPath()];

    global = [settings objectForKey:@"global"] ? [[settings objectForKey:@"global"] boolValue] : NO;
    NSInteger savedStyle = DNSMigrateSwitchStyle(
        [settings objectForKey:@"switchStyle"] ? [[settings objectForKey:@"switchStyle"] integerValue] : 0
    );
    switchStyle = DNSIsValidSwitchStyle(savedStyle) ? savedStyle : 0;
    DNSDiag(@"readPrefs", @{@"file": DNSPrefsPath(), @"hasFile": @(settings != nil)});
}

static void DNSPrefsChanged(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    DNSDiag(@"darwinNotify", nil);
    dispatch_async(dispatch_get_main_queue(), ^{
        DNSReadPrefs();
        [[NSNotificationCenter defaultCenter] postNotificationName:DNSPrefsChangedNotification object:nil];
    });
}

%ctor {
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, DNSPrefsChanged, CFSTR("de.finngaida.daynightswitch/settingschanged"), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
    DNSReadPrefs();
}

@interface UISwitch (DayNightSwitch)
// 【修复编译报错】：去掉 <>，使用 UIView 绕过 Theos 解析器 Bug
@property (nonatomic, retain) UIView *dns_dayNightSwitch;
@property (nonatomic, retain) NSNumber *dns_currentStyle;
- (BOOL)dns_shouldApply;
- (void)dns_setup;
- (void)dns_addSwitch;
- (void)dns_removeSwitch;
- (void)dns_preferencesChanged;
- (void)dns_restoreNativeAppearance;
- (void)dns_syncCustomSwitchWithOn:(BOOL)on animated:(BOOL)animated;
@property (nonatomic, retain) UIColor *dns_originalTintColor;
@property (nonatomic, retain) UIColor *dns_originalOnTintColor;
@property (nonatomic, retain) UIColor *dns_originalThumbTintColor;
@property (nonatomic, retain) NSNumber *dns_appearanceCaptured;
@property (nonatomic, retain) NSNumber *dns_originalShadowOpacity;
@end

%hook UISwitch

// 兼容部分 Logos / iOS 组合：不用 %property，直接走 associated object。
%new
- (UIView *)dns_dayNightSwitch {
    return objc_getAssociatedObject(self, &DNSDayNightSwitchKey);
}

%new
- (void)setDns_dayNightSwitch:(UIView *)view {
    objc_setAssociatedObject(self, &DNSDayNightSwitchKey, view, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

%new
- (NSNumber *)dns_currentStyle {
    return objc_getAssociatedObject(self, &DNSCurrentStyleKey);
}

%new
- (UIColor *)dns_originalTintColor {
    return objc_getAssociatedObject(self, &DNSOriginalTintColorKey);
}

%new
- (UIColor *)dns_originalOnTintColor {
    return objc_getAssociatedObject(self, &DNSOriginalOnTintColorKey);
}

%new
- (UIColor *)dns_originalThumbTintColor {
    return objc_getAssociatedObject(self, &DNSOriginalThumbTintColorKey);
}

%new
- (NSNumber *)dns_appearanceCaptured {
    return objc_getAssociatedObject(self, &DNSAppearanceCapturedKey);
}

%new
- (NSNumber *)dns_originalShadowOpacity {
    return objc_getAssociatedObject(self, &DNSOriginalShadowOpacityKey);
}

%new
- (void)setDns_currentStyle:(NSNumber *)value {
    objc_setAssociatedObject(self, &DNSCurrentStyleKey, value, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

%new
- (void)setDns_originalTintColor:(UIColor *)value {
    objc_setAssociatedObject(self, &DNSOriginalTintColorKey, value, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

%new
- (void)setDns_originalOnTintColor:(UIColor *)value {
    objc_setAssociatedObject(self, &DNSOriginalOnTintColorKey, value, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

%new
- (void)setDns_originalThumbTintColor:(UIColor *)value {
    objc_setAssociatedObject(self, &DNSOriginalThumbTintColorKey, value, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

%new
- (void)setDns_appearanceCaptured:(NSNumber *)value {
    objc_setAssociatedObject(self, &DNSAppearanceCapturedKey, value, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

%new
- (void)setDns_originalShadowOpacity:(NSNumber *)value {
    objc_setAssociatedObject(self, &DNSOriginalShadowOpacityKey, value, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (void)didMoveToSuperview {
    %orig;
    DNSDiag(@"didMoveToSuperview", @{@"shouldApply": @([self dns_shouldApply])});
    [self dns_setup];
}

%new
- (BOOL)dns_shouldApply {
    if (global) {
        return YES;
    }

    NSString *bundleId = [[NSBundle mainBundle] bundleIdentifier];
    if (![bundleId isEqual:@"com.apple.Preferences"]) {
        return NO;
    }

    PSSwitchTableCell *cell = (PSSwitchTableCell *)self.superview;
    if (![cell respondsToSelector:@selector(specifier)] || ![cell respondsToSelector:@selector(control)]) {
        return NO;
    }

    PSSpecifier *spec = [cell specifier];
    if (![spec respondsToSelector:@selector(identifier)]) {
        return NO;
    }

    NSString *identifier = [spec identifier];
    if (![identifier isKindOfClass:[NSString class]]) {
        return NO;
    }

    id control = [cell control];
    return [identifier isEqual:@"DND_TOP_LEVEL"] && control == self;
}

%new
- (void)dns_setup {
    [[NSNotificationCenter defaultCenter] removeObserver:self name:DNSPrefsChangedNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(dns_preferencesChanged) name:DNSPrefsChangedNotification object:nil];

    if (![self dns_shouldApply]) {
        if (self.dns_dayNightSwitch) {
            DNSDiag(@"dns_setup_remove", @{@"reason": @"shouldApply_false"});
            [self dns_removeSwitch];
        }
        return;
    }

    if (self.dns_dayNightSwitch) {
        DNSDiag(@"dns_setup_sync", nil);
        [self dns_syncCustomSwitchWithOn:self.on animated:NO];
        return;
    }

    DNSDiag(@"dns_setup_add", nil);
    [self dns_addSwitch];
}

%new
- (void)dns_removeSwitch {
    UIView *customSwitch = self.dns_dayNightSwitch;
    if (customSwitch) {
        [customSwitch removeFromSuperview];
    }
    self.dns_dayNightSwitch = nil;
    self.dns_currentStyle = nil;
    [self dns_restoreNativeAppearance];
}

%new
- (void)dns_preferencesChanged {
    NSInteger oldStyle = [self.dns_currentStyle integerValue];
    BOOL hadCustomSwitch = (self.dns_dayNightSwitch != nil);

    if (![self dns_shouldApply]) {
        [self dns_removeSwitch];
        return;
    }

    if (!hadCustomSwitch) {
        [self dns_setup];
        return;
    }

    if (oldStyle != switchStyle) {
        [self dns_removeSwitch];
        [self dns_setup];
    }
}

%new
- (void)dns_addSwitch {
    UIView<FGASwitchProtocol> *sub;

    Class subClass = nil;
    if (switchStyle == 1) {
        subClass = [StripedSwitch class];
        sub = (UIView<FGASwitchProtocol> *)[[StripedSwitch alloc] initWithFrame:CGRectMake(0, 0, 51, 31)];
    } else if (switchStyle == 2) {
        subClass = [DongRiYueSwitch class];
        sub = (UIView<FGASwitchProtocol> *)[[DongRiYueSwitch alloc] initWithFrame:CGRectMake(0, 0, 51, 31)];
    } else if (switchStyle == 3) {
        subClass = [PlaneSwitch class];
        sub = (UIView<FGASwitchProtocol> *)[[PlaneSwitch alloc] initWithFrame:CGRectMake(0, 0, 51, 31)];
    } else if (switchStyle == 4) {
        subClass = [TeethSwitch class];
        sub = (UIView<FGASwitchProtocol> *)[[TeethSwitch alloc] initWithFrame:CGRectMake(0, 0, 51, 31)];
    } else {
        subClass = [DayNightSwitch class];
        sub = (UIView<FGASwitchProtocol> *)[[DayNightSwitch alloc] initWithFrame:CGRectMake(0, 0, 51, 31)];
    }
    sub.on = self.on;

    __weak __typeof(self) weakSelf = self;
    sub.changeAction = ^(BOOL on, BOOL shouldNotifyChanged) {
        __strong __typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }

        BOOL wasOn = strongSelf.on;
        if (wasOn != on) {
            [strongSelf setOn:on animated:YES];
        }

        if (shouldNotifyChanged) {
            [strongSelf sendActionsForControlEvents:UIControlEventValueChanged];
        }
    };

    self.dns_dayNightSwitch = sub;
    self.dns_currentStyle = @(switchStyle);

    if (!self.dns_appearanceCaptured.boolValue) {
        self.dns_originalTintColor = self.tintColor;
        self.dns_originalOnTintColor = self.onTintColor;
        self.dns_originalThumbTintColor = self.thumbTintColor;
        self.dns_originalShadowOpacity = @(self.layer.shadowOpacity);
        self.dns_appearanceCaptured = @YES;
    }
    self.tintColor = [UIColor clearColor];
    self.onTintColor = [UIColor clearColor];
    self.thumbTintColor = [UIColor clearColor];
    [self addSubview:sub];
    DNSDiag(@"dns_addSwitch", @{@"subClass": NSStringFromClass(subClass), @"subFrame": NSStringFromCGRect(sub.frame)});
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self name:DNSPrefsChangedNotification object:nil];
    %orig;
}

- (void)layoutSubviews {
    %orig;
    UIView *customSwitch = self.dns_dayNightSwitch;
    if (customSwitch) {
        self.tintColor = [UIColor clearColor];
        self.onTintColor = [UIColor clearColor];
        self.thumbTintColor = [UIColor clearColor];
        customSwitch.frame = self.bounds;
        [self bringSubviewToFront:customSwitch];
        DNSDiag(@"layoutSubviews", @{@"hasCustom": @YES, @"bounds": NSStringFromCGRect(self.bounds)});
    } else {
        DNSDiag(@"layoutSubviews", @{@"hasCustom": @NO});
    }
}

%new
- (void)dns_restoreNativeAppearance {
    UIColor *tintColor = self.dns_originalTintColor;
    UIColor *onTintColor = self.dns_originalOnTintColor;
    UIColor *thumbTintColor = self.dns_originalThumbTintColor;
    self.tintColor = tintColor;
    self.onTintColor = onTintColor;
    self.thumbTintColor = thumbTintColor;
    self.layer.shadowOpacity = self.dns_originalShadowOpacity.floatValue;
    self.dns_originalTintColor = nil;
    self.dns_originalOnTintColor = nil;
    self.dns_originalThumbTintColor = nil;
    self.dns_originalShadowOpacity = nil;
    self.dns_appearanceCaptured = nil;
}

%new
- (void)dns_syncCustomSwitchWithOn:(BOOL)on animated:(BOOL)animated {
    id customSwitch = self.dns_dayNightSwitch;
    if (!customSwitch) return;

    if (![customSwitch respondsToSelector:@selector(blockChangeActionAnimated:)] ||
        ![customSwitch respondsToSelector:@selector(unblockChangeAction)] ||
        ![customSwitch respondsToSelector:@selector(setOn:)]) {
        return;
    }

    [((id)customSwitch) blockChangeActionAnimated:animated];
    if ([((id)customSwitch) respondsToSelector:@selector(setOn:animated:)]) {
        [(id)customSwitch setOn:on animated:animated];
    } else {
        [customSwitch setOn:on];
    }
    [((id)customSwitch) unblockChangeAction];
}

- (void)setOn:(BOOL)arg1 {
    %orig;
    [self dns_syncCustomSwitchWithOn:arg1 animated:NO];
}

- (void)setOn:(BOOL)arg1 animated:(BOOL)arg2 {
    %orig;
    [self dns_syncCustomSwitchWithOn:arg1 animated:arg2];
}
%end

// MTAAlarmTableViewCell hook 已移除：同步走 UISwitch setOn: / setOn:animated: 钩子即可
