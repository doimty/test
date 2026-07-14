#include "InsulationCtlArgs.h"

#include <stddef.h>
#include <string.h>

static void InsulationCtlInitResult(InsulationCtlParseResult *result) {
    result->action = INSULATION_CTL_ACTION_STATUS;
    result->mode = INSULATION_CTL_MODE_OFF;
    result->raw = false;
    result->quiet = false;
    result->exitCode = INSULATION_CTL_EXIT_OK;
    result->errorMessage = NULL;
}

static int InsulationCtlSetUsageError(InsulationCtlParseResult *result, const char *message) {
    result->action = INSULATION_CTL_ACTION_ERROR;
    result->exitCode = INSULATION_CTL_EXIT_USAGE;
    result->errorMessage = message;
    return result->exitCode;
}

static bool InsulationCtlIsHelpAction(const char *arg) {
    return strcmp(arg, "help") == 0 || strcmp(arg, "--help") == 0 || strcmp(arg, "-h") == 0;
}

static bool InsulationCtlModeFromArg(const char *arg, InsulationCtlMode *modeOut) {
    if (strcmp(arg, "off") == 0) {
        *modeOut = INSULATION_CTL_MODE_OFF;
        return true;
    }
    if (strcmp(arg, "low") == 0 || strcmp(arg, "lowPower") == 0) {
        *modeOut = INSULATION_CTL_MODE_LOW_POWER;
        return true;
    }
    if (strcmp(arg, "max") == 0 || strcmp(arg, "fullPower") == 0) {
        *modeOut = INSULATION_CTL_MODE_FULL_POWER;
        return true;
    }
    return false;
}

int InsulationCtlParseArgs(int argc, const char *const argv[], InsulationCtlParseResult *result) {
    if (!result) {
        return INSULATION_CTL_EXIT_USAGE;
    }
    InsulationCtlInitResult(result);

    bool sawAction = false;
    for (int i = 1; i < argc; i++) {
        const char *arg = argv[i];
        if (!arg || arg[0] == '\0') {
            return InsulationCtlSetUsageError(result, "empty argument");
        }

        if (strcmp(arg, "--raw") == 0) {
            result->raw = true;
            continue;
        }
        if (strcmp(arg, "--quiet") == 0) {
            result->quiet = true;
            continue;
        }
        if (InsulationCtlIsHelpAction(arg)) {
            if (sawAction) {
                return InsulationCtlSetUsageError(result, "multiple actions specified");
            }
            result->action = INSULATION_CTL_ACTION_HELP;
            sawAction = true;
            continue;
        }
        if (strcmp(arg, "--reset-native-state") == 0) {
            if (sawAction || result->raw || result->quiet) {
                return InsulationCtlSetUsageError(result, "native-state reset cannot be combined with other arguments");
            }
            result->action = INSULATION_CTL_ACTION_RESET_NATIVE;
            sawAction = true;
            continue;
        }
        if (arg[0] == '-') {
            return InsulationCtlSetUsageError(result, "unknown option");
        }
        if (sawAction) {
            return InsulationCtlSetUsageError(result, "multiple actions specified");
        }
        if (strcmp(arg, "status") == 0) {
            result->action = INSULATION_CTL_ACTION_STATUS;
            sawAction = true;
            continue;
        }
        InsulationCtlMode mode = INSULATION_CTL_MODE_OFF;
        if (InsulationCtlModeFromArg(arg, &mode)) {
            result->action = INSULATION_CTL_ACTION_SET_MODE;
            result->mode = mode;
            sawAction = true;
            continue;
        }
        return InsulationCtlSetUsageError(result, "unknown action or mode");
    }

    if (result->action == INSULATION_CTL_ACTION_RESET_NATIVE && (result->raw || result->quiet)) {
        return InsulationCtlSetUsageError(result, "native-state reset cannot be combined with other arguments");
    }

    result->exitCode = INSULATION_CTL_EXIT_OK;
    result->errorMessage = NULL;
    return result->exitCode;
}

const char *InsulationCtlModeDisplayName(InsulationCtlMode mode) {
    switch (mode) {
        case INSULATION_CTL_MODE_LOW_POWER:
            return "low";
        case INSULATION_CTL_MODE_FULL_POWER:
            return "max";
        case INSULATION_CTL_MODE_OFF:
        default:
            return "off";
    }
}

const char *InsulationCtlModePrefsValue(InsulationCtlMode mode) {
    switch (mode) {
        case INSULATION_CTL_MODE_LOW_POWER:
            return "lowPower";
        case INSULATION_CTL_MODE_FULL_POWER:
            return "fullPower";
        case INSULATION_CTL_MODE_OFF:
        default:
            return "off";
    }
}

void InsulationCtlModeFromPrefsValue(const char *prefsValue, InsulationCtlMode *modeOut) {
    if (!modeOut) {
        return;
    }
    if (prefsValue && strcmp(prefsValue, "lowPower") == 0) {
        *modeOut = INSULATION_CTL_MODE_LOW_POWER;
        return;
    }
    if (prefsValue && strcmp(prefsValue, "fullPower") == 0) {
        *modeOut = INSULATION_CTL_MODE_FULL_POWER;
        return;
    }
    *modeOut = INSULATION_CTL_MODE_OFF;
}
