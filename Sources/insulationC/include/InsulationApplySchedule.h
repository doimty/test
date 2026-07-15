#ifndef INSULATION_APPLY_SCHEDULE_H
#define INSULATION_APPLY_SCHEDULE_H

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
    InsulationApplyScheduleEventDirectApply = 0,
    InsulationApplyScheduleEventBeginSoon,
    InsulationApplyScheduleEventCancelSoon,
} InsulationApplyScheduleEvent;

typedef struct {
    uint64_t generation;
} InsulationApplyScheduleState;

InsulationApplyScheduleState InsulationApplyScheduleStateInitial(void);

/* The caller must serialize state access on the apply queue. */
uint64_t InsulationApplyScheduleStep(InsulationApplyScheduleState *state,
                                     InsulationApplyScheduleEvent event);
bool InsulationApplyScheduleAccepts(const InsulationApplyScheduleState *state,
                                    uint64_t token);

#ifdef __cplusplus
}
#endif

#endif
