#include <stdbool.h>
#include <stdio.h>

#include "InsulationCPUState.h"

static int failures;

#define CHECK(condition, label) \
    do { \
        if (!(condition)) { \
            fprintf(stderr, "FAIL: %s (line %d)\n", label, __LINE__); \
            failures++; \
        } \
    } while (0)

static void test_fresh_off_waits_for_controller(void) {
    InsulationCPUState state = InsulationCPUStateInitial();
    InsulationCPUStep step = InsulationCPUStateStep(&state, InsulationCPUModeOff, false, false, 4);

    CHECK(step.action == InsulationCPUActionWait, "fresh off waits without controller");
    CHECK(step.resetObservedPower, "fresh off resets observations");
    CHECK(state.hasAppliedMode, "fresh off records an applied mode");
    CHECK(state.appliedMode == InsulationCPUModeOff, "fresh off records off");
    CHECK(state.phase == InsulationCPUPhaseBoot, "fresh off stays in boot phase");
    CHECK(state.pendingRestoreCount == 4, "fresh off arms all restore passes");
}

static void test_fresh_off_completes_four_restores(void) {
    InsulationCPUState state = InsulationCPUStateInitial();
    int expectedRemaining[] = {3, 2, 1, 0};
    for (int index = 0; index < 4; index++) {
        InsulationCPUStep step = InsulationCPUStateStep(&state, InsulationCPUModeOff, false, true, 4);
        CHECK(step.action == InsulationCPUActionRestoreOff, "off performs restore");
        CHECK(step.remainingRestoreCount == expectedRemaining[index], "off restore count decrements");
    }
    CHECK(state.phase == InsulationCPUPhaseSteady, "off becomes steady after four restores");
}

static void test_full_power_warmup_does_not_fake_off(void) {
    InsulationCPUState state = InsulationCPUStateInitial();
    InsulationCPUStep guarded = InsulationCPUStateStep(&state, InsulationCPUModeFullPower, true, true, 4);
    CHECK(guarded.action == InsulationCPUActionWait, "full power guard waits");
    CHECK(!state.hasAppliedMode, "guard does not invent an applied mode");
    CHECK(state.phase == InsulationCPUPhaseBoot, "guard remains in boot phase");

    InsulationCPUStep active = InsulationCPUStateStep(&state, InsulationCPUModeFullPower, false, true, 4);
    CHECK(active.action == InsulationCPUActionApplyFullPower, "full power applies after guard");
    CHECK(state.hasAppliedMode && state.appliedMode == InsulationCPUModeFullPower, "full power records applied mode");
    CHECK(state.phase == InsulationCPUPhaseSteady, "full power becomes steady");
}

static void test_leaving_full_power_restores_four_times(void) {
    InsulationCPUState state = InsulationCPUStateInitial();
    (void)InsulationCPUStateStep(&state, InsulationCPUModeFullPower, false, true, 4);

    InsulationCPUStep first = InsulationCPUStateStep(&state, InsulationCPUModeOff, false, true, 4);
    CHECK(first.action == InsulationCPUActionRestoreOff, "leaving full power starts restore");
    CHECK(state.phase == InsulationCPUPhaseLeaving, "leaving full power uses leaving phase");
    CHECK(first.remainingRestoreCount == 3, "first leaving restore leaves three passes");

    for (int index = 0; index < 3; index++) {
        (void)InsulationCPUStateStep(&state, InsulationCPUModeOff, false, true, 4);
    }
    CHECK(state.pendingRestoreCount == 0, "leaving restore drains");
    CHECK(state.phase == InsulationCPUPhaseSteady, "leaving restore reaches steady");
}

static void test_mode_change_cancels_pending_restore(void) {
    InsulationCPUState state = InsulationCPUStateInitial();
    (void)InsulationCPUStateStep(&state, InsulationCPUModeOff, false, false, 4);
    CHECK(state.pendingRestoreCount == 4, "off restore is pending");

    InsulationCPUStep low = InsulationCPUStateStep(&state, InsulationCPUModeLowPower, false, true, 4);
    CHECK(low.action == InsulationCPUActionApplyLowPower, "low power applies");
    CHECK(state.pendingRestoreCount == 0, "low power cancels off restore");
    CHECK(state.phase == InsulationCPUPhaseSteady, "low power is steady");
}

static void test_full_to_low_applies_without_restore(void) {
    InsulationCPUState state = InsulationCPUStateInitial();
    (void)InsulationCPUStateStep(&state, InsulationCPUModeFullPower, false, true, 4);

    InsulationCPUStep low = InsulationCPUStateStep(&state, InsulationCPUModeLowPower, false, true, 4);
    CHECK(low.action == InsulationCPUActionApplyLowPower, "full to low applies low mode");
    CHECK(low.resetObservedPower, "full to low resets observed maxima");
    CHECK(state.appliedMode == InsulationCPUModeLowPower, "full to low records low mode");
    CHECK(state.pendingRestoreCount == 0, "full to low does not arm off restore");
}

static void test_low_to_off_restores_four_times(void) {
    InsulationCPUState state = InsulationCPUStateInitial();
    (void)InsulationCPUStateStep(&state, InsulationCPUModeLowPower, false, true, 4);

    for (int index = 0; index < 4; index++) {
        InsulationCPUStep off = InsulationCPUStateStep(&state, InsulationCPUModeOff, false, true, 4);
        CHECK(off.action == InsulationCPUActionRestoreOff, "low to off performs restore");
        if (index == 0) {
            CHECK(off.phase == InsulationCPUPhaseLeaving, "low to off enters leaving phase");
        }
    }
    CHECK(state.pendingRestoreCount == 0, "low to off drains restore count");
    CHECK(state.phase == InsulationCPUPhaseSteady, "low to off reaches steady");
}

static void test_restart_rearms_fresh_off_restores(void) {
    InsulationCPUState oldProcess = InsulationCPUStateInitial();
    (void)InsulationCPUStateStep(&oldProcess, InsulationCPUModeFullPower, false, true, 4);
    InsulationCPUStep oldOff = InsulationCPUStateStep(&oldProcess, InsulationCPUModeOff, false, true, 4);
    CHECK(oldOff.remainingRestoreCount == 3, "old process completes one leaving restore before restart");

    InsulationCPUState newProcess = InsulationCPUStateInitial();
    int restoreActions = 0;
    for (int index = 0; index < 4; index++) {
        InsulationCPUStep freshOff = InsulationCPUStateStep(&newProcess, InsulationCPUModeOff, false, true, 4);
        if (freshOff.action == InsulationCPUActionRestoreOff) {
            restoreActions++;
        }
    }
    CHECK(restoreActions == 4, "new process rearms all four fresh-off restores");
    CHECK(newProcess.phase == InsulationCPUPhaseSteady, "new process fresh-off restore reaches steady");
}

int main(void) {
    test_fresh_off_waits_for_controller();
    test_fresh_off_completes_four_restores();
    test_full_power_warmup_does_not_fake_off();
    test_leaving_full_power_restores_four_times();
    test_mode_change_cancels_pending_restore();
    test_full_to_low_applies_without_restore();
    test_low_to_off_restores_four_times();
    test_restart_rearms_fresh_off_restores();

    if (failures != 0) {
        fprintf(stderr, "%d CPU state test(s) failed\n", failures);
        return 1;
    }
    puts("All CPU state tests passed.");
    return 0;
}
