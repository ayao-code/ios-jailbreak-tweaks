#include "ASGPolicy.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>

int main(void) {
    ASGSession session = {.generation = 4, .deadline = 4, .active = true};
    assert(ASGSessionValid(&session, 4, 0));
    assert(!ASGSessionValid(&session, 3, 0));
    assert(!ASGSessionValid(&session, 4, 4));
    assert(!ASGSessionValid(&session, 4, NAN));
    for (unsigned i = 0; i < ASG_MAX_PROBES; i++) assert(ASGConsumeProbe(&session, 1));
    assert(!ASGConsumeProbe(&session, 1));
    ASGCancelSession(&session);
    assert(!ASGSessionValid(&session, 4, 1));
    assert(session.generation == 5 && !session.active);
    assert(ASGCornerButton(.75, .05, .15, .05));
    assert(ASGCornerButton(.05, .05, .15, .05));
    assert(!ASGCornerButton(.45, .05, .15, .05));
    assert(!ASGCornerButton(.75, .75, .15, .05));
    assert(!ASGRectValid(NAN, 0, .1, .1));
    assert(!ASGRectValid(-.1, 0, .1, .1));
    assert(!ASGRectValid(0, 0, 0, .1));
    assert(!ASGRectValid(.9, 0, .2, .1));
    assert(!ASGMayPromote(1, true, false));
    assert(!ASGMayPromote(2, false, false));
    assert(!ASGMayPromote(2, true, true));
    assert(ASGMayPromote(2, true, false));
    assert(ASGOCRResultValid(5, 5, 1, true));
    assert(!ASGOCRResultValid(5, 4, 1, true));
    assert(!ASGOCRResultValid(5, 5, 2, true));
    assert(!ASGOCRResultValid(5, 5, 1, false));
    assert(!ASGOCRResultValid(5, 5, NAN, true));
    assert(ASGOCRPairAgrees(.8, true, true));
    assert(!ASGOCRPairAgrees(.8, false, true));
    assert(!ASGOCRPairAgrees(.3, true, true));
    assert(!ASGOCRPairAgrees(.8, true, false));
    assert(ASGShouldAttemptSkip(true, true, true, true, true, false));
    assert(ASGShouldAttemptSkip(true, true, true, true, false, true));
    assert(!ASGShouldAttemptSkip(true, true, false, true, true, false));
    assert(!ASGShouldAttemptSkip(true, false, true, true, true, true));
    assert(!ASGShouldAttemptSkip(false, true, true, true, true, true));
    assert(!ASGShouldAttemptSkip(true, true, true, false, true, true));
    assert(ASGAdCloseButton(.4, .74, .2, .03)); // Observed Guazi centered-modal close.
    assert(!ASGCornerButton(.4, .74, .2, .03));
    assert(!ASGAdCloseButton(0, 0, .9, .7)); // Do not click an entire overlay.
    assert(ASGSuccessFeedback(true, true, true, true, true, true));
    assert(!ASGSuccessFeedback(false, true, true, true, true, true));
    assert(!ASGSuccessFeedback(true, false, true, true, true, true));
    assert(!ASGSuccessFeedback(true, true, false, true, true, true));
    assert(!ASGSuccessFeedback(true, true, true, false, true, true));
    assert(!ASGSuccessFeedback(true, true, true, true, false, true));
    assert(!ASGSuccessFeedback(true, true, true, true, true, false));
    assert(ASGAuthorizeCandidate(false, false, true, false, false, .7, .1, .2, .04));
    assert(ASGAuthorizeCandidate(false, true, false, false, false, .4, .74, .2, .04));
    assert(ASGAuthorizeCandidate(true, false, false, false, false, .4, .1, .2, .04));
    assert(!ASGAuthorizeCandidate(false, false, false, false, false, .7, .1, .2, .04));
    assert(!ASGAuthorizeCandidate(true, false, false, false, true, .7, .1, .2, .04));
    assert(ASGAuthorizeCandidate(true, false, false, true, true, .7, .1, .2, .04));
    assert(!ASGAuthorizeCandidate(true, true, true, true, false, 0, 0, .9, .8));
    assert(ASGExitEvidenceSafe(4, .55));
    assert(!ASGExitEvidenceSafe(1, .12));
    assert(!ASGExitEvidenceSafe(2, 1.21));
    assert(!ASGExitEvidenceSafe(4, NAN));
    double firstSeen = -1;
    assert(!ASGObserveExit(&firstSeen, .4, false));
    assert(!ASGObserveExit(&firstSeen, .6, true));
    assert(ASGObserveExit(&firstSeen, .85, true)); // Actual 0.6s exit is no longer missed.
    assert(!ASGObserveExit(&firstSeen, .9, false)); // Reappearing ad resets evidence.
    assert(!ASGObserveExit(&firstSeen, 1.0, true));
    assert(!ASGObserveExit(&firstSeen, 1.1, true));
    ASGSession bounded = {.generation=10, .deadline=ASG_ACTIVE_SECONDS, .active=true};
    assert(ASG_ACTIVE_SECONDS == 8.0);
    assert(ASGSessionValid(&bounded, 10, 5.0));
    assert(ASGSessionValid(&bounded, 10, 7.999));
    assert(!ASGSessionValid(&bounded, 10, 8.0));
    assert(!ASGConsumeProbe(&bounded, 8.01));
    // The probe cap must not silently expire the new window around 6 seconds.
    for (unsigned i = 0; i < 20; i++) assert(ASGConsumeProbe(&bounded, .15 + .4 * i));
    assert(ASG_MAX_IMAGE_WIDTH * ASG_MAX_IMAGE_HEIGHT * 4 == 6144000);
    assert(ASGAdCountdownEntry(false, .8, .06, .15, .04));
    assert(!ASGAdCountdownEntry(false, .45, .5, .1, .04));
    assert(ASGAdCountdownEntry(true, .45, .5, .1, .04));
    assert(!ASGAdCountdownEntry(true, 0, 0, .9, .8));
    assert(!ASGAuthorizeCandidate(false, false, false, false, false, .75, .08, .15, .04));
    unsigned char imageBefore[8192] = {0}, imageAfter[8192] = {0};
    assert(ASGVisualEvidenceMatches(imageBefore, imageAfter, 8192));
    imageAfter[0] = 1;
    assert(ASGVisualEvidenceMatches(imageBefore, imageAfter, 8192));
    for (unsigned i = 0; i < 300; i++) imageAfter[i] = 255;
    assert(!ASGVisualEvidenceMatches(imageBefore, imageAfter, 8192));
    assert(!ASGVisualEvidenceMatches(NULL, imageAfter, 8192));
    assert(!ASGVisualEvidenceMatches(imageBefore, imageAfter, 256));
    puts("PASS policy: generation, deadlines, bounded probes, rectangles, uncertain promotion, stale OCR, changed-page/changed-position rejection");
    return 0;
}
