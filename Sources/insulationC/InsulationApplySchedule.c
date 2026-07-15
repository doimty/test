#include "include/InsulationApplySchedule.h"

#include <stddef.h>

InsulationApplyScheduleState InsulationApplyScheduleStateInitial(void) {
    InsulationApplyScheduleState state = {
        .generation = 0,
    };
    return state;
}

uint64_t InsulationApplyScheduleStep(InsulationApplyScheduleState *state,
                                     InsulationApplyScheduleEvent event) {
    if (state == NULL) {
        return 0;
    }

    switch (event) {
        case InsulationApplyScheduleEventBeginSoon:
        case InsulationApplyScheduleEventCancelSoon:
            state->generation += 1;
            break;
        case InsulationApplyScheduleEventDirectApply:
            break;
    }
    return state->generation;
}

bool InsulationApplyScheduleAccepts(const InsulationApplyScheduleState *state,
                                    uint64_t token) {
    return state != NULL && token == state->generation;
}
