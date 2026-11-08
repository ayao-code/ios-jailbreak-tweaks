#include "ASGPolicy.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>

int main(void) {
    ASGSession session = {.generation=9, .deadline=8, .active=true};
    ASGOCRSchedule schedule;
    ASGResetOCRSchedule(&schedule, 0);
    assert(schedule.misses == 0 && schedule.nextAt == .5);
    assert(!ASGOCRDue(&schedule, &session, 9, .49, false));
    assert(ASGOCRDue(&schedule, &session, 9, .5, false));
    assert(!ASGOCRDue(&schedule, &session, 9, .5, true));
    assert(!ASGOCRDue(&schedule, &session, 8, .5, false));
    session.verifying = true;
    assert(!ASGOCRDue(&schedule, &session, 9, .5, false));
    session.verifying = false;
    // A slow request must wait from completion, never from its start.
    assert(ASGCompleteOCRMiss(&schedule, 1.4) == .25);
    assert(schedule.nextAt == 1.65);
    assert(!ASGOCRDue(&schedule, &session, 9, 1.64, false));
    assert(ASGOCRDue(&schedule, &session, 9, 1.65, false));
    assert(ASGCompleteOCRMiss(&schedule, 2) == .5);
    assert(schedule.nextAt == 2.5);
    assert(ASGCompleteOCRMiss(&schedule, 2.6) == 1);
    for (unsigned i = 0; i < 10000; i++) assert(ASGCompleteOCRMiss(&schedule, 3) == 1);
    assert(schedule.misses == 3 && schedule.nextAt == 4);
    assert(!ASGOCRDue(&schedule, &session, 9, 8, false));
    ASGCancelSession(&session);
    assert(!ASGOCRDue(&schedule, &session, 9, 4, false));
    ASGResetOCRSchedule(&schedule, NAN);
    assert(isinf(schedule.nextAt));
    assert(isinf(ASGCompleteOCRMiss(NULL, 1)));
    ASGResetOCRSchedule(&schedule, 0);
    session = (ASGSession){.generation=11, .deadline=8, .active=true};
    unsigned discoveries = 0;
    double now = .5;
    while (ASGOCRDue(&schedule, &session, 11, now, false)) {
        discoveries++;
        now += .01; // Very fast OCR still cannot busy-loop.
        ASGCompleteOCRMiss(&schedule, now);
        now = schedule.nextAt;
    }
    assert(discoveries > 6 && discoveries < 16);
    printf("PASS OCR schedule: completion-based .25/.5/1s cooldown, cap, single-flight, expiry, cancellation, %u discoveries beyond sixth\n", discoveries);
}
