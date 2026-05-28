#import <objc/runtime.h>
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
static char DNSBypassKey;

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

static void loadPrefs(void) {
    NSMutableDictionary *settings = [[NSMutableDictionary alloc] initWithContentsOfFile:DNSPrefsPath()];
    enabled = [settings objectForKey:@"enabled"] ? [[settings objectForKey:@"enabled"] boolValue] : YES;
    global = [settings objectForKey:@"global"] ? [[settings objectForKey:@"global"] boolValue] : NO;

    // 读取样式：0 是日夜交替，1 是清新条纹
    switchStyle = [settings objectForKey:@"switchStyle"] ? [[settings objectForKey:@"switchStyle"] integerValue] : 0;
}

%ctor {
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, (CFNotificationCallback)loadPrefs, CFSTR("de.finngaida.daynightswitch/settingschanged"), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
    loadPrefs();
}

@interface UISwitch (DayNightSwitch)
// 【修复编译报错】：去掉 <>，使用 UIView 绕过 Theos 解析器 Bug
@property (nonatomic, retain) UIView *dns_dayNightSwitch;
@property (nonatomic, retain) NSNumber *dns_bypass;
- (void)dns_setup;
- (void)dns_addSwitch;
- (void)dns_syncCustomSwitchWithOn:(BOOL)on animated:(BOOL)animated;
- (void)dns_sendImpactFeedback;
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
- (NSNumber *)dns_bypass {
    return objc_getAssociatedObject(self, &DNSBypassKey);
}

%new
- (void)setDns_bypass:(NSNumber *)value {
    objc_setAssociatedObject(self, &DNSBypassKey, value, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (void)didMoveToSuperview {
    %orig;
    [self dns_setup];
}

%new
- (void)dns_setup {
    if (enabled && !self.dns_dayNightSwitch) {
        NSString *bundleId = [[NSBundle mainBundle] bundleIdentifier];
        if (global) {
            [self dns_addSwitch];
        } else if ([bundleId isEqual: @"com.apple.Preferences"]) {
            PSSwitchTableCell *cell = (PSSwitchTableCell *)self.superview;
            if ([cell respondsToSelector:@selector(specifier)] && [cell respondsToSelector:@selector(control)]) {
                id spec = [cell performSelector:@selector(specifier)];
                if ([spec respondsToSelector:@selector(identifier)]) {
                    NSString *identifier = [spec performSelector:@selector(identifier)];
                    if ([identifier isEqual:@"DND_TOP_LEVEL"] && [cell performSelector:@selector(control)] == self) {
                        [self dns_addSwitch];
                    }
                }
            }
        }
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
    self.dns_bypass = @YES;
    sub.on = self.on;
    self.dns_bypass = nil;

    __weak __typeof(self) weakSelf = self;
    sub.changeAction = ^(BOOL on, BOOL shouldNotifyChanged) {
        __strong __typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }

        strongSelf.dns_bypass = @YES;
        BOOL isOn = strongSelf.on;
        strongSelf.on = on;
        strongSelf.dns_bypass = nil;

        // iOS 15 兼容：不要直接调用 UISwitch 私有 _impactFeedbackGenerator。
        if (isOn != on) {
            [strongSelf dns_sendImpactFeedback];
        }

        if (shouldNotifyChanged) {
            [strongSelf sendActionsForControlEvents:UIControlEventValueChanged];
        }
    };

    self.dns_dayNightSwitch = sub;

    self.layer.shadowOpacity = 0;
    [self addSubview:sub];
}

- (void)layoutSubviews {
    %orig;
    UIView *customSwitch = self.dns_dayNightSwitch;
    if (customSwitch) {
        customSwitch.frame = self.bounds;
        [self bringSubviewToFront:customSwitch];
    }
}

%new
- (void)dns_sendImpactFeedback {
    UIImpactFeedbackGenerator *generator = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
    [generator prepare];
    [generator impactOccurred];
}

%new
- (void)dns_syncCustomSwitchWithOn:(BOOL)on animated:(BOOL)animated {
    if ([self.dns_bypass boolValue]) {
        return;
    }

    id customSwitch = self.dns_dayNightSwitch;
    if (!customSwitch ||
        ![customSwitch respondsToSelector:@selector(blockChangeActionAnimated:)] ||
        ![customSwitch respondsToSelector:@selector(setOn:)] ||
        ![customSwitch respondsToSelector:@selector(unblockChangeAction)]) {
        return;
    }

    id<FGASwitchProtocol> typedSwitch = (id<FGASwitchProtocol>)customSwitch;
    [typedSwitch blockChangeActionAnimated:animated];
    [typedSwitch setOn:on];
    [typedSwitch unblockChangeAction];
}

- (void)setOn:(BOOL)arg1 animated:(BOOL)arg2 {
    %orig;
    [self dns_syncCustomSwitchWithOn:arg1 animated:arg2];
}


%end

