#ifndef INSULATION_CPU_STATE_H
#define INSULATION_CPU_STATE_H

#include <stdbool.h>

typedef enum {
    InsulationCPUModeOff,
    InsulationCPUModeLowPower,
    InsulationCPUModeFullPower,
} InsulationCPUMode;

typedef enum {
    InsulationCPUPhaseBoot,
    InsulationCPUPhaseSteady,
    InsulationCPUPhaseLeaving,
} InsulationCPUPhase;

typedef enum {
    InsulationCPUActionWait,
    InsulationCPUActionApplyLowPower,
    InsulationCPUActionApplyFullPower,
    InsulationCPUActionRestoreOff,
} InsulationCPUAction;

typedef struct {
    bool hasAppliedMode;
    InsulationCPUMode appliedMode;
    InsulationCPUPhase phase;
    int pendingRestoreCount;
} InsulationCPUState;

typedef struct {
    InsulationCPUAction action;
    InsulationCPUPhase phase;
    bool resetObservedPower;
    int remainingRestoreCount;
} InsulationCPUStep;

InsulationCPUState InsulationCPUStateInitial(void);
InsulationCPUStep InsulationCPUStateStep(InsulationCPUState *state,
                                        InsulationCPUMode requestedMode,
                                        bool fullPowerGuardActive,
                                        bool controllerAvailable,
                                        int restoreEventCount);

#endif
