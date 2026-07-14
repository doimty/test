#include "include/InsulationCPUState.h"

InsulationCPUState InsulationCPUStateInitial(void) {
    InsulationCPUState state = {
        .hasAppliedMode = false,
        .appliedMode = InsulationCPUModeOff,
        .phase = InsulationCPUPhaseBoot,
        .pendingRestoreCount = 0,
    };
    return state;
}

static InsulationCPUStep InsulationCPUStepForState(const InsulationCPUState *state,
                                                   InsulationCPUAction action,
                                                   bool resetObservedPower) {
    InsulationCPUStep step = {
        .action = action,
        .phase = state->phase,
        .resetObservedPower = resetObservedPower,
        .remainingRestoreCount = state->pendingRestoreCount,
    };
    return step;
}

InsulationCPUStep InsulationCPUStateStep(InsulationCPUState *state,
                                        InsulationCPUMode requestedMode,
                                        bool fullPowerGuardActive,
                                        bool controllerAvailable,
                                        int restoreEventCount) {
    bool modeChanged = !state->hasAppliedMode || state->appliedMode != requestedMode;

    if (requestedMode == InsulationCPUModeFullPower && fullPowerGuardActive) {
        state->phase = InsulationCPUPhaseBoot;
        state->pendingRestoreCount = 0;
        return InsulationCPUStepForState(state, InsulationCPUActionWait, modeChanged);
    }

    if (requestedMode == InsulationCPUModeFullPower) {
        state->hasAppliedMode = true;
        state->appliedMode = requestedMode;
        state->phase = InsulationCPUPhaseSteady;
        state->pendingRestoreCount = 0;
        return InsulationCPUStepForState(state, InsulationCPUActionApplyFullPower, modeChanged);
    }

    if (requestedMode == InsulationCPUModeLowPower) {
        state->hasAppliedMode = true;
        state->appliedMode = requestedMode;
        state->phase = InsulationCPUPhaseSteady;
        state->pendingRestoreCount = 0;
        return InsulationCPUStepForState(state, InsulationCPUActionApplyLowPower, modeChanged);
    }

    bool freshProcess = !state->hasAppliedMode;
    bool leavingOverride = state->hasAppliedMode && state->appliedMode != InsulationCPUModeOff;
    if ((freshProcess || leavingOverride) && state->pendingRestoreCount <= 0) {
        state->pendingRestoreCount = restoreEventCount > 0 ? restoreEventCount : 1;
        state->phase = freshProcess ? InsulationCPUPhaseBoot : InsulationCPUPhaseLeaving;
    }
    state->hasAppliedMode = true;
    state->appliedMode = InsulationCPUModeOff;

    if (state->pendingRestoreCount <= 0) {
        state->phase = InsulationCPUPhaseSteady;
        return InsulationCPUStepForState(state, InsulationCPUActionWait, modeChanged);
    }
    if (!controllerAvailable) {
        return InsulationCPUStepForState(state, InsulationCPUActionWait, modeChanged);
    }

    state->pendingRestoreCount -= 1;
    if (state->pendingRestoreCount == 0) {
        state->phase = InsulationCPUPhaseSteady;
    }
    return InsulationCPUStepForState(state, InsulationCPUActionRestoreOff, modeChanged);
}
