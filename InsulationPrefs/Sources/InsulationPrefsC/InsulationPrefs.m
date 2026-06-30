#import "include/InsulationPrefs.h"

#include <notify.h>

static const char *InsulationRuntimeStateName = "com.be-huge.insulation.runtimeState";
static const uint64_t InsulationRuntimeStateMagic = 0x494E535500000000ULL;

int insulationPrefsPostRuntimeState(int thermalMode, int cpuMode) {
    int token = 0;
    int status = notify_register_check(InsulationRuntimeStateName, &token);
    if (status != NOTIFY_STATUS_OK) {
        return status;
    }

    uint64_t state = InsulationRuntimeStateMagic |
        (((uint64_t)(thermalMode & 0xff)) << 8) |
        ((uint64_t)(cpuMode & 0xff));

    status = notify_set_state(token, state);
    if (status == NOTIFY_STATUS_OK) {
        status = notify_post(InsulationRuntimeStateName);
    }
    notify_cancel(token);
    return status;
}
