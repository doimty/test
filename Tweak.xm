#import <objc/runtime.h>
#import <spawn.h>
#import <stdlib.h>
#import "DayNightSwitch.h" // 原版自带效果
#import "StripedSwitch.h"  // 新版条纹效果
#import "DongRiYueSwitch.h"
#import "PlaneSwitch.h"
#import "MagicSwitch.h"
#import "FoodSwitch.h"
#import "BB8Switch.h"
#import "NavSwitch.h"
#import "TeethSwitch.h"
#import "XiXiSwitch.h"
#import "DoggoSwitch.h"


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
@optional
- (void)dns_disableAnimations;
@end
// =======================================================================

// MARK: Settings
static BOOL enabled = NO;
static BOOL global = NO;
static NSInteger switchStyle = 0; // 新增：保存用户选择的样式

static NSString *DNSPrefsPath(void) {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *mobilePath = @"/var/mobile/Library/Preferences/de.finngaida.daynightswitch.plist";
    if ([fm fileExistsAtPath:mobilePath]) {
        return mobilePath;
    }
    return @"/var/jb/var/mobile/Library/Preferences/de.finngaida.daynightswitch.plist";
}

static void DNSReadPrefs(void) {
    NSMutableDictionary *settings = [[NSMutableDictionary alloc] initWithContentsOfFile:DNSPrefsPath()];
    enabled = [settings objectForKey:@"enabled"] ? [[settings objectForKey:@"enabled"] boolValue] : YES;
    global = [settings objectForKey:@"global"] ? [[settings objectForKey:@"global"] boolValue] : NO;

    // 读取样式：0 是日夜交替，1 是清新条纹
    switchStyle = [settings objectForKey:@"switchStyle"] ? [[settings objectForKey:@"switchStyle"] integerValue] : 0;
}

static void DNSPrefsChanged(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    DNSReadPrefs();
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:DNSPrefsChangedNotification object:nil];
    });
}

static void DNSRunRespringCommand(void) {
    NSArray<NSArray<NSString *> *> *commands = @[
        @[@"/var/jb/usr/bin/sbreload"],
        @[@"/usr/bin/sbreload"],
        @[@"/var/jb/usr/bin/ldrestart"],
        @[@"/usr/bin/ldrestart"],
        @[@"/var/jb/usr/bin/killall", @"-9", @"SpringBoard"],
        @[@"/usr/bin/killall", @"-9", @"SpringBoard"],
        @[@"/bin/killall", @"-9", @"SpringBoard"]
    ];

    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSArray<NSString *> *command in commands) {
        NSString *path = command.firstObject;
        if (![fm fileExistsAtPath:path]) {
            continue;
        }

        NSUInteger count = command.count;
        char **args = calloc(count + 1, sizeof(char *));
        if (!args) {
            return;
        }
        for (NSUInteger i = 0; i < count; i++) {
            args[i] = (char *)[command[i] UTF8String];
        }
        args[count] = NULL;

        pid_t pid = 0;
        int status = posix_spawn(&pid, [path fileSystemRepresentation], NULL, NULL, args, NULL);
        free(args);
        if (status == 0) {
            return;
        }
    }
}

static void DNSRespringRequested(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        DNSRunRespringCommand();
    });
}

%ctor {
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, DNSPrefsChanged, CFSTR("de.finngaida.daynightswitch/settingschanged"), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, DNSRespringRequested, CFSTR("de.finngaida.daynightswitch/respring"), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
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
- (void)dns_disableCustomSwitchAnimationsForAlarmCell;
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
    } else if (switchStyle == 4) {
        // 对应 4: 日月交替
        sub = (UIView<FGASwitchProtocol> *)[[MagicSwitch alloc] initWithFrame:CGRectMake(0, 0, 51, 31)];
    } else if (switchStyle == 5) {
        // 对应 5: 汉堡薯条
        sub = (UIView<FGASwitchProtocol> *)[[FoodSwitch alloc] initWithFrame:CGRectMake(0, 0, 51, 31)];
    } else if (switchStyle == 6) {
        // 对应 6: 星战机器人 (BB-8)
        sub = (UIView<FGASwitchProtocol> *)[[BB8Switch alloc] initWithFrame:CGRectMake(0, 0, 51, 31)];
    } else if (switchStyle == 7) {
        // 对应 7: 星夜火箭
        sub = (UIView<FGASwitchProtocol> *)[[NavSwitch alloc] initWithFrame:CGRectMake(0, 0, 51, 31)];
    } else if (switchStyle == 8) {
        // 对应 8: 纯洁牙齿
        sub = (UIView<FGASwitchProtocol> *)[[TeethSwitch alloc] initWithFrame:CGRectMake(0, 0, 51, 31)];
    } else if (switchStyle == 9) {
        // 对应 9: 嘻嘻
        sub = (UIView<FGASwitchProtocol> *)[[XiXiSwitch alloc] initWithFrame:CGRectMake(0, 0, 51, 31)];
    } else if (switchStyle == 10) {
        // 对应 9: 狗狗翻滚
        sub = (UIView<FGASwitchProtocol> *)[[DoggoSwitch alloc] initWithFrame:CGRectMake(0, 0, 51, 31)];
    } else {
        // 默认对应 0 (以及 9~10 的敬请期待): 日夜交替 (静态)
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
    %orig;
    UIView *customSwitch = self.dns_dayNightSwitch;
    if (customSwitch) {
        customSwitch.frame = self.bounds;
        [self dns_syncCustomSwitchWithOn:self.on animated:NO];
        [self bringSubviewToFront:customSwitch];
    }
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
    if (!customSwitch ||
        ![customSwitch respondsToSelector:@selector(blockChangeActionAnimated:)] ||
        ![customSwitch respondsToSelector:@selector(setOn:)] ||
        ![customSwitch respondsToSelector:@selector(unblockChangeAction)]) {
        return;
    }

    id<FGASwitchProtocol> typedSwitch = (id<FGASwitchProtocol>)customSwitch;
    [typedSwitch blockChangeActionAnimated:animated];
    if ([typedSwitch respondsToSelector:@selector(setOn:animated:)]) {
        [(id)typedSwitch setOn:on animated:animated];
    } else {
        [typedSwitch setOn:on];
    }
    [typedSwitch unblockChangeAction];
}

%new
- (void)dns_disableCustomSwitchAnimationsForAlarmCell {
    id customSwitch = self.dns_dayNightSwitch;
    if ([customSwitch respondsToSelector:@selector(dns_disableAnimations)]) {
        [(id)customSwitch dns_disableAnimations];
        [self dns_syncCustomSwitchWithOn:self.on animated:NO];
    }
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

static UISwitch *DNSFindSwitchWithCustomDayNightSkin(UIView *view) {
    if ([view isKindOfClass:[UISwitch class]] && [view respondsToSelector:@selector(dns_disableCustomSwitchAnimationsForAlarmCell)]) {
        UISwitch *switchView = (UISwitch *)view;
        if ([switchView respondsToSelector:@selector(dns_dayNightSwitch)] && [(id)switchView dns_dayNightSwitch]) {
            return switchView;
        }
    }
    for (UIView *subview in view.subviews) {
        UISwitch *foundSwitch = DNSFindSwitchWithCustomDayNightSkin(subview);
        if (foundSwitch) {
            return foundSwitch;
        }
    }
    return nil;
}

@interface MTAAlarmTableViewCell : UITableViewCell
@end

%hook MTAAlarmTableViewCell

- (void)layoutSubviews {
    %orig;

    UISwitch *switchView = DNSFindSwitchWithCustomDayNightSkin(self.contentView);
    if (switchView) {
        [(id)switchView dns_disableCustomSwitchAnimationsForAlarmCell];
    }
}

%end

