#ifndef INSULATION_CTL_ARGS_H
#define INSULATION_CTL_ARGS_H

#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
    INSULATION_CTL_EXIT_OK = 0,
    INSULATION_CTL_EXIT_USAGE = 64,
    INSULATION_CTL_EXIT_IO = 74,
    INSULATION_CTL_EXIT_NOTIFY = 75,
} InsulationCtlExitCode;

typedef enum {
    INSULATION_CTL_ACTION_ERROR = 0,
    INSULATION_CTL_ACTION_STATUS,
    INSULATION_CTL_ACTION_SET_MODE,
    INSULATION_CTL_ACTION_RESET_NATIVE,
    INSULATION_CTL_ACTION_HELP,
} InsulationCtlAction;

typedef enum {
    INSULATION_CTL_MODE_OFF = 0,
    INSULATION_CTL_MODE_LOW_POWER,
    INSULATION_CTL_MODE_FULL_POWER,
} InsulationCtlMode;

typedef struct {
    InsulationCtlAction action;
    InsulationCtlMode mode;
    bool raw;
    bool quiet;
    int exitCode;
    const char *errorMessage;
} InsulationCtlParseResult;

int InsulationCtlParseArgs(int argc, const char *const argv[], InsulationCtlParseResult *result);
const char *InsulationCtlModeDisplayName(InsulationCtlMode mode);
const char *InsulationCtlModePrefsValue(InsulationCtlMode mode);
void InsulationCtlModeFromPrefsValue(const char *prefsValue, InsulationCtlMode *modeOut);

#ifdef __cplusplus
}
#endif

#endif
