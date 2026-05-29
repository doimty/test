#import "FGARootListController.h"

#import <Preferences/PSSpecifier.h>


#import <spawn.h>
#import <notify.h>

extern char **environ;

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
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
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
            int status = posix_spawn(&pid, [path fileSystemRepresentation], NULL, NULL, args, environ);
            free(args);
            if (status == 0) {
                return;
            }
        }
    });
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
