#import <objc/runtime.h>
#import <CoreFoundation/CoreFoundation.h>
#import "DayNightSwitch.h"
#import "StripedSwitch.h"
#import "DongRiYueSwitch.h"
#import "PlaneSwitch.h"
#import "TeethSwitch.h"


@interface PSSwitchTableCell : UITableViewCell
- (SEL)cellAction;
@end

@interface PSSpecifier : NSObject
@end

static char DNSDayNightSwitchKey;
static char DNSCurrentStyleKey;
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
static BOOL enabled = NO;
static BOOL global = NO;
static NSInteger switchStyle = 0; // 新增：保存用户选择的样式

// 恢复 DNSPrefsPath：使用 plist 文件直接读取配置
// 注意：fdf730f 版本工作正常，改用 CFPreferencesCopyAppValue 后部分进程读不到 global=YES

static NSString *DNSPrefsPath(void) {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *mobilePath = @"/var/mobile/Library/Preferences/de.finngaida.daynightswitch.plist";
    if ([fm fileExistsAtPath:mobilePath]) {
        return mobilePath;
    }
    return @"/var/jb/var/mobile/Library/Preferences/de.finngaida.daynightswitch.plist";
}

static void DNSReadPrefs(void) {
    CFPreferencesAppSynchronize(CFSTR("de.finngaida.daynightswitch"));
    NSMutableDictionary *settings = [[NSMutableDictionary alloc] initWithContentsOfFile:DNSPrefsPath()];
    enabled = [settings objectForKey:@"enabled"] ? [[settings objectForKey:@"enabled"] boolValue] : YES;
    global = [settings objectForKey:@"global"] ? [[settings objectForKey:@"global"] boolValue] : NO;
    switchStyle = [settings objectForKey:@"switchStyle"] ? [[settings objectForKey:@"switchStyle"] integerValue] : 0;
}

static void DNSPrefsChanged(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    DNSReadPrefs();
    dispatch_async(dispatch_get_main_queue(), ^{
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
- (void)setDns_currentStyle:(NSNumber *)value {
    objc_setAssociatedObject(self, &DNSCurrentStyleKey, value, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (void)didMoveToSuperview {
    %orig;
    [self dns_setup];
}

%new
- (BOOL)dns_shouldApply {
    if (!enabled) {
        return NO;
    }

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

    id spec = [cell performSelector:@selector(specifier)];
    if (![spec respondsToSelector:@selector(identifier)]) {
        return NO;
    }

    NSString *identifier = [spec performSelector:@selector(identifier)];
    return [identifier isEqual:@"DND_TOP_LEVEL"] && [cell performSelector:@selector(control)] == self;
}

%new
- (void)dns_setup {
    if (![self dns_shouldApply]) {
        if (self.dns_dayNightSwitch) {
            [self dns_removeSwitch];
        }
        return;
    }

    if (self.dns_dayNightSwitch) {
        // UITableView/UICollectionView 复用 cell 时，同一个 UISwitch 会被重新绑定到别的数据行。
        // 这里每次回到视图层级都强制按系统 UISwitch 的真实状态刷新自定义视图，避免闹钟列表这种场景串状态。
        [self dns_syncCustomSwitchWithOn:self.on animated:NO];
        return;
    }

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
    [[NSNotificationCenter defaultCenter] removeObserver:self name:DNSPrefsChangedNotification object:nil];
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

    // 【指挥部】：这里的数字已经和你的 Root.plist 完全对齐
    if (switchStyle == 1) {
        // 对应 1: 清晰条纹
        sub = (UIView<FGASwitchProtocol> *)[[StripedSwitch alloc] initWithFrame:CGRectMake(0, 0, 51, 31)];
    } else if (switchStyle == 2) {
        // 对应 2: 日夜交替 (动态)
        sub = (UIView<FGASwitchProtocol> *)[[DongRiYueSwitch alloc] initWithFrame:CGRectMake(0, 0, 51, 31)];
    } else if (switchStyle == 3) {
        // 对应 3: 飞机跑道
        sub = (UIView<FGASwitchProtocol> *)[[PlaneSwitch alloc] initWithFrame:CGRectMake(0, 0, 51, 31)];
    } else if (switchStyle == 8) {
        // 对应 8: 纯洁牙齿
        sub = (UIView<FGASwitchProtocol> *)[[TeethSwitch alloc] initWithFrame:CGRectMake(0, 0, 51, 31)];
    } else {
        // 默认 0: 经典日月
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

        if (shouldNotifyChanged && wasOn != on) {
            [strongSelf sendActionsForControlEvents:UIControlEventValueChanged];
        }
    };

    self.dns_dayNightSwitch = sub;
    self.dns_currentStyle = @(switchStyle);
    [[NSNotificationCenter defaultCenter] removeObserver:self name:DNSPrefsChangedNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(dns_preferencesChanged) name:DNSPrefsChangedNotification object:nil];

    self.layer.shadowOpacity = 0;
    self.tintColor = [UIColor clearColor];
    self.onTintColor = [UIColor clearColor];
    self.thumbTintColor = [UIColor clearColor];
    [self addSubview:sub];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self name:DNSPrefsChangedNotification object:nil];
    %orig;
}

- (void)layoutSubviews {
    UIView *customSwitch = self.dns_dayNightSwitch;
    if (customSwitch) {
        // 在 %orig 之前把自定义开关放好、隐藏原生开关外观，防止原生闪烁
        self.tintColor = [UIColor clearColor];
        self.onTintColor = [UIColor clearColor];
        self.thumbTintColor = [UIColor clearColor];
        customSwitch.frame = self.bounds;
        [self bringSubviewToFront:customSwitch];
    }
    %orig;
}

%new
- (void)dns_restoreNativeAppearance {
    self.tintColor = nil;
    self.onTintColor = nil;
    self.thumbTintColor = nil;
}

%new
- (void)dns_syncCustomSwitchWithOn:(BOOL)on animated:(BOOL)animated {
    id customSwitch = self.dns_dayNightSwitch;
    if (!customSwitch) return;

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
