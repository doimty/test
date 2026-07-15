#include <stdbool.h>
#include <stdio.h>

#include "InsulationApplySchedule.h"
#include "InsulationCPUState.h"

static int failures;

#define CHECK(condition, label) \
    do { \
        if (!(condition)) { \
            fprintf(stderr, "FAIL: %s (line %d)\n", label, __LINE__); \
            failures++; \
        } \
    } while (0)

static void test_direct_apply_does_not_cancel_soon_batch(void) {
    InsulationApplyScheduleState schedule = InsulationApplyScheduleStateInitial();
    uint64_t startupToken = InsulationApplyScheduleStep(&schedule, InsulationApplyScheduleEventBeginSoon);

    (void)InsulationApplyScheduleStep(&schedule, InsulationApplyScheduleEventDirectApply);
    (void)InsulationApplyScheduleStep(&schedule, InsulationApplyScheduleEventDirectApply);

    CHECK(InsulationApplyScheduleAccepts(&schedule, startupToken),
          "direct apply preserves the active Soon batch");
}

static void test_new_soon_batch_supersedes_old_batch(void) {
    InsulationApplyScheduleState schedule = InsulationApplyScheduleStateInitial();
    uint64_t oldToken = InsulationApplyScheduleStep(&schedule, InsulationApplyScheduleEventBeginSoon);
    uint64_t newToken = InsulationApplyScheduleStep(&schedule, InsulationApplyScheduleEventBeginSoon);

    CHECK(!InsulationApplyScheduleAccepts(&schedule, oldToken),
          "new Soon batch supersedes the old batch");
    CHECK(InsulationApplyScheduleAccepts(&schedule, newToken),
          "new Soon batch remains active");
}

static void test_explicit_cancel_invalidates_soon_batch(void) {
    InsulationApplyScheduleState schedule = InsulationApplyScheduleStateInitial();
    uint64_t token = InsulationApplyScheduleStep(&schedule, InsulationApplyScheduleEventBeginSoon);

    (void)InsulationApplyScheduleStep(&schedule, InsulationApplyScheduleEventCancelSoon);

    CHECK(!InsulationApplyScheduleAccepts(&schedule, token),
          "explicit cancellation invalidates the Soon batch");
}

static void test_startup_callers_reach_off_steady_state(void) {
    InsulationApplyScheduleState schedule = InsulationApplyScheduleStateInitial();
    InsulationCPUState cpu = InsulationCPUStateInitial();
    uint64_t startupToken = InsulationApplyScheduleStep(&schedule, InsulationApplyScheduleEventBeginSoon);

    /* CommonProduct direct apply occurs before the controller exists. */
    (void)InsulationApplyScheduleStep(&schedule, InsulationApplyScheduleEventDirectApply);
    (void)InsulationCPUStateStep(&cpu, InsulationCPUModeOff, false, false, 4);
    CHECK(cpu.pendingRestoreCount == 4, "fresh off arms four restores before controller capture");

    /* Controller capture and its direct replay accelerate two restore passes. */
    (void)InsulationApplyScheduleStep(&schedule, InsulationApplyScheduleEventDirectApply);
    (void)InsulationCPUStateStep(&cpu, InsulationCPUModeOff, false, true, 4);
    (void)InsulationApplyScheduleStep(&schedule, InsulationApplyScheduleEventDirectApply);
    (void)InsulationCPUStateStep(&cpu, InsulationCPUModeOff, false, true, 4);

    for (int index = 0; index < 4; index++) {
        if (InsulationApplyScheduleAccepts(&schedule, startupToken)) {
            (void)InsulationCPUStateStep(&cpu, InsulationCPUModeOff, false, true, 4);
        }
    }

    CHECK(cpu.pendingRestoreCount == 0, "startup caller composition drains all restores");
    CHECK(cpu.phase == InsulationCPUPhaseSteady, "startup caller composition reaches steady off");
}

int main(void) {
    test_direct_apply_does_not_cancel_soon_batch();
    test_new_soon_batch_supersedes_old_batch();
    test_explicit_cancel_invalidates_soon_batch();
    test_startup_callers_reach_off_steady_state();

    if (failures != 0) {
        fprintf(stderr, "%d apply-schedule test(s) failed\n", failures);
        return 1;
    }
    puts("All apply-schedule tests passed.");
    return 0;
}
