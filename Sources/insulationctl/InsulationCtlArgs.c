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

static const char InsulationCtlPrefsSystemPath[] =
    "/var/mobile/Library/Preferences/com.be-huge.insulation-prefs.plist";

const char *InsulationCtlPrefsFilePath(void) {
    return InsulationCtlPrefsSystemPath;
}

int InsulationCtlPrefsPathIsRedirected(const char *path) {
    return path && strstr(path, "/.jbroot-") != NULL;
}

int InsulationCtlJbrootPrefixFromPath(const char *path, char *out, unsigned long outSize) {
    const char *found;
    const char *name;
    const char *slash;
    size_t prefixLen;
    if (!path || !out || outSize == 0) {
        return 0;
    }
    found = strstr(path, "/.jbroot-");
    if (!found) {
        return 0;
    }
    name = found + 1;
    if (strncmp(name, ".jbroot-", 8) != 0 || name[8] == '\0' || name[8] == '/') {
        return 0;
    }
    slash = strchr(name, '/');
    prefixLen = slash ? (size_t)(slash - path) : strlen(path);
    if (prefixLen + 1 > outSize) {
        return 0;
    }
    memcpy(out, path, prefixLen);
    out[prefixLen] = '\0';
    return 1;
}

int InsulationCtlResolvePrefsPath(const char *executablePath, char *out, unsigned long outSize) {
    const char *systemPath = InsulationCtlPrefsSystemPath;
    size_t systemLen = strlen(systemPath);
    char prefix[4096];
    size_t prefixLen;
    if (!out || outSize == 0) {
        return 0;
    }
    if (InsulationCtlJbrootPrefixFromPath(executablePath, prefix, sizeof(prefix))) {
        prefixLen = strlen(prefix);
        if (prefixLen + systemLen + 1 > outSize) {
            return 0;
        }
        memcpy(out, prefix, prefixLen);
        memcpy(out + prefixLen, systemPath, systemLen + 1);
        return 1;
    }
    if (systemLen + 1 > outSize) {
        return 0;
    }
    memcpy(out, systemPath, systemLen + 1);
    return 0;
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
