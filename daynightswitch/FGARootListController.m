#import "FGARootListController.h"

#import <Preferences/PSSpecifier.h>

#import <notify.h>

static NSString *const DNSPrefsChangedDarwinNotification = @"de.finngaida.daynightswitch/settingschanged";

@implementation FGARootListController

- (NSArray *)specifiers {
    if (!_specifiers) {
        _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    }

    return _specifiers;
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    [super setPreferenceValue:value specifier:specifier];
    notify_post([DNSPrefsChangedDarwinNotification UTF8String]);
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
