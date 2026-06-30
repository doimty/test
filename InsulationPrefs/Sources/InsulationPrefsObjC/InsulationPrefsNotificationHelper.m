#import "InsulationPrefsNotificationHelper.h"
#import "InsulationPrefsParams.h"
#import "../InsulationPrefsC/include/InsulationPrefs.h"

void InsulationPrefsPostDarwinNotification(NSString *name) {
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge CFStringRef)name, NULL, NULL, true);
}

void InsulationPrefsPostApplyNotifications(void) {
    insulationPrefsPostRuntimeState(0, 0);
    InsulationPrefsPostDarwinNotification(InsulationPrefsExecuteNotification);
}

void InsulationPrefsPostRestartNotifications(void) {
    InsulationPrefsPostDarwinNotification(InsulationPrefsRestartNotification);
}
