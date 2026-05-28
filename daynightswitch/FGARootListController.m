#import "FGARootListController.h"

#import <Preferences/PSSpecifier.h>


#import <spawn.h>
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

- (void)respring {
    pid_t pid;
    NSArray<NSString *> *candidates = @[@"/var/jb/usr/bin/sbreload", @"/usr/bin/sbreload", @"/var/jb/usr/bin/killall", @"/usr/bin/killall", @"/bin/killall"];
    NSString *toolPath = nil;
    for (NSString *path in candidates) {
        if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
            toolPath = path;
            break;
        }
    }
    if (!toolPath) {
        return;
    }

    const char *args[4];
    if ([[toolPath lastPathComponent] isEqualToString:@"sbreload"]) {
        args[0] = "sbreload";
        args[1] = NULL;
    } else {
        args[0] = "killall";
        args[1] = "-9";
        args[2] = "SpringBoard";
        args[3] = NULL;
    }
    posix_spawn(&pid, [toolPath fileSystemRepresentation], NULL, NULL, (char *const *)args, NULL);
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

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0) {
        PSSpecifier *specifier = [self specifierAtIndexPath:indexPath];
        NSString *key = [specifier propertyForKey:@"cell"];
        if ([key isEqualToString:@"PSButtonCell"]) {
            UITableViewCell *cell = [super tableView:tableView cellForRowAtIndexPath:indexPath];
            NSNumber *isDestructiveValue = [specifier propertyForKey:@"isDestructive"];
            BOOL isDestructive = [isDestructiveValue boolValue];
            cell.textLabel.textColor = isDestructive ? [UIColor systemRedColor] : [UIColor systemBlueColor];
            cell.textLabel.highlightedTextColor = isDestructive ? [UIColor systemRedColor] : [UIColor systemBlueColor];
            return cell;
        }
    }
    return [super tableView:tableView cellForRowAtIndexPath:indexPath];
}

@end
