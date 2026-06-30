#import "InsulationPrefsParams.h"
#import "../InsulationPrefsC/include/InsulationPrefs.h"

NSString *const InsulationPrefsPowerModeKey = @"thermalPowerMode";
NSString *const InsulationPrefsExecuteNotification = @"com.be-huge.insulation-executePuppetEvent";
NSString *const InsulationPrefsRestartNotification = @"com.be-huge.insulation-restartThermalMonitor";

NSString *InsulationPrefsPlistPath(void) {
    return rootlessPath(@"/var/mobile/Library/Preferences/com.be-huge.insulation-prefs.plist");
}
