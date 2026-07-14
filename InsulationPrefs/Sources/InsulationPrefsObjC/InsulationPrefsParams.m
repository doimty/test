#import "InsulationPrefsParams.h"
#import "../InsulationPrefsC/include/InsulationPrefs.h"

NSString *const InsulationPrefsPowerModeKey = @"thermalPowerMode";
NSString *const InsulationPrefsExecuteNotification = @"com.be-huge.insulation-executePuppetEvent";
NSString *const InsulationPrefsModeChangeNotification = @"com.be-huge.insulation-modeDidChange";

NSString *InsulationPrefsPlistPath(void) {
    return rootlessPath(@"/var/mobile/Library/Preferences/com.be-huge.insulation-prefs.plist");
}
