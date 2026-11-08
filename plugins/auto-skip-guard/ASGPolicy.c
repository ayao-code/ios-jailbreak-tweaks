#include "ASGPolicy.h"
#include <math.h>

bool ASGSessionValid(const ASGSession *s, uint64_t token, double now) {
    return s && s->active && s->generation == token && isfinite(now) && now < s->deadline;
}

bool ASGConsumeProbe(ASGSession *s, double now) {
    if (!s || !ASGSessionValid(s, s->generation, now) || s->verifying || s->probes >= ASG_MAX_PROBES) return false;
    s->probes++;
    return true;
}

void ASGResetOCRSchedule(ASGOCRSchedule *schedule, double startedAt) {
    if (!schedule) return;
    schedule->nextAt = isfinite(startedAt) ? startedAt + .5 : INFINITY;
    schedule->misses = 0;
}

double ASGCompleteOCRMiss(ASGOCRSchedule *schedule, double completedAt) {
    if (!schedule || !isfinite(completedAt)) return INFINITY;
    double delay = schedule->misses == 0 ? .25 : (schedule->misses == 1 ? .5 : 1.0);
    if (schedule->misses < 3) schedule->misses++; // Saturate, don't shift or overflow.
    schedule->nextAt = completedAt + delay;
    return delay;
}

bool ASGOCRDue(const ASGOCRSchedule *schedule, const ASGSession *session,
               uint64_t token, double now, bool inFlight) {
    return schedule && ASGSessionValid(session, token, now) && !inFlight
        && !session->verifying && isfinite(schedule->nextAt) && now >= schedule->nextAt;
}

bool ASGRectValid(double x, double y, double w, double h) {
    return isfinite(x) && isfinite(y) && isfinite(w) && isfinite(h)
        && x >= 0 && y >= 0 && w > 0 && h > 0 && x + w <= 1.001 && y + h <= 1.001;
}

bool ASGCornerButton(double x, double y, double w, double h) {
    if (!ASGRectValid(x, y, w, h)) return false;
    return w <= 0.40 && h <= 0.16 && y + h <= 0.30 && (x + w <= 0.40 || x >= 0.60);
}

bool ASGAdCloseButton(double x, double y, double w, double h) {
    return ASGRectValid(x, y, w, h) && w <= 0.50 && h <= 0.18;
}

bool ASGSuccessFeedback(bool dispatched, bool samePage, bool targetGone, bool containerGone, bool active, bool stable) {
    return dispatched && samePage && targetGone && containerGone && active && stable;
}

bool ASGMayPromote(unsigned confirmations, bool verified, bool uncertain) {
    return confirmations >= 2 && verified && !uncertain;
}

bool ASGOCRResultValid(uint64_t current, uint64_t result, double age, bool samePage) {
    return current == result && isfinite(age) && age >= 0 && age <= 1.5 && samePage;
}

bool ASGOCRPairAgrees(double overlap, bool sameMeaning, bool samePage) {
    return isfinite(overlap) && overlap >= 0.65 && overlap <= 1 && sameMeaning && samePage;
}

bool ASGShouldAttemptSkip(bool visible, bool unique, bool skipSemantic, bool userInteraction, bool countdown, bool enabled) {
    (void)countdown;
    (void)enabled;
    // A valid skip is attempted even during countdown. A successful result is checked separately.
    return visible && unique && skipSemantic && userInteraction;
}

void ASGCancelSession(ASGSession *s) {
    if (!s) return;
    s->active = false;
    s->verifying = false;
    s->generation++;
}

bool ASGAuthorizeCandidate(bool skip, bool explicitAd, bool countdown, bool overlay, bool arrow,
                          double x, double y, double w, double h) {
    if (!ASGRectValid(x, y, w, h) || w > .65 || h > .20) return false;
    // Width/height refer to the text entry, not the potentially fullscreen canvas hit view.
    if (explicitAd) return true;
    if (arrow) return overlay || countdown;
    if (!skip) return countdown || overlay; // overlay must be independently confirmed as ad context.
    return overlay || countdown || y + h <= .30;
}

bool ASGExitEvidenceSafe(int seconds, double elapsed) {
    if (!isfinite(elapsed) || elapsed < 0) return false;
    return seconds < 0 || (seconds >= 2 && elapsed + .8 < seconds);
}

bool ASGObserveExit(double *firstSeen, double now, bool evidence) {
    if (!firstSeen || !isfinite(now)) return false;
    if (!evidence) { *firstSeen = -1; return false; }
    if (*firstSeen < 0) { *firstSeen = now; return false; }
    return now >= *firstSeen && now - *firstSeen >= .15;
}

bool ASGAdCountdownEntry(bool adContext, double x, double y, double w, double h) {
    if (!ASGRectValid(x, y, w, h) || w > .40 || h > .12) return false;
    // An explicit ad+unit phrase in a small upper corner is a candidate by itself.
    // Elsewhere it additionally needs an identified ad context, not any large ancestor.
    return adContext || (y + h <= .30 && (x >= .60 || x + w <= .40));
}

bool ASGVisualEvidenceMatches(const unsigned char *before, const unsigned char *after, unsigned length) {
    if (!before || !after || length != 8192) return false;
    unsigned total = 0, changed = 0;
    for (unsigned i = 0; i < length; i++) {
        unsigned difference = before[i] > after[i] ? before[i] - after[i] : after[i] - before[i];
        total += difference;
        if (difference > 12) changed++;
    }
    // A cheap conservative sampled-pixel witness, not a cryptographic content version.
    return total <= length * 2 && changed * 100 <= length * 2;
}
