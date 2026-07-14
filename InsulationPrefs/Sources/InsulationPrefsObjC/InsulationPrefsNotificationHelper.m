#import "InsulationPrefsNotificationHelper.h"
#import "InsulationPrefsParams.h"

void InsulationPrefsPostDarwinNotification(NSString *name) {
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge CFStringRef)name, NULL, NULL, true);
}

void InsulationPrefsPostApplyNotifications(void) {
    InsulationPrefsPostDarwinNotification(InsulationPrefsExecuteNotification);
}

void InsulationPrefsPostModeChangeNotification(void) {
    InsulationPrefsPostDarwinNotification(InsulationPrefsModeChangeNotification);
}
