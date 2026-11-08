#ifndef ASG_POLICY_H
#define ASG_POLICY_H
#include <stdbool.h>
#include <stdint.h>
#define ASG_ACTIVE_SECONDS 8.0
#define ASG_MAX_PROBES 48
#define ASG_MAX_IMAGE_WIDTH 960.0
#define ASG_MAX_IMAGE_HEIGHT 1600.0
#define ASG_MAX_DIAGNOSTIC_BYTES 16384

typedef struct {
    uint64_t generation;
    double deadline;
    unsigned probes;
    bool active;
    bool verifying;
} ASGSession;

typedef struct {
    double nextAt;
    unsigned misses;
} ASGOCRSchedule;

void ASGResetOCRSchedule(ASGOCRSchedule *schedule, double startedAt);
double ASGCompleteOCRMiss(ASGOCRSchedule *schedule, double completedAt);
bool ASGOCRDue(const ASGOCRSchedule *schedule, const ASGSession *session,
               uint64_t token, double now, bool inFlight);

bool ASGSessionValid(const ASGSession *session, uint64_t token, double now);
bool ASGConsumeProbe(ASGSession *session, double now);
bool ASGRectValid(double x, double y, double width, double height);
bool ASGCornerButton(double x, double y, double width, double height);
bool ASGAdCloseButton(double x, double y, double width, double height);
bool ASGSuccessFeedback(bool dispatched, bool samePage, bool targetGone, bool containerGone, bool active, bool sceneStable);
bool ASGMayPromote(unsigned confirmations, bool verified, bool uncertain);
bool ASGOCRResultValid(uint64_t currentToken, uint64_t resultToken, double age, bool samePage);
bool ASGOCRPairAgrees(double overlap, bool sameMeaning, bool samePage);
bool ASGShouldAttemptSkip(bool visible, bool unique, bool skipSemantic, bool userInteraction, bool countdown, bool enabled);
bool ASGAuthorizeCandidate(bool skip, bool explicitAd, bool countdown, bool overlay, bool arrow,
                          double x, double y, double width, double height);
bool ASGExitEvidenceSafe(int seconds, double elapsed);
bool ASGObserveExit(double *firstSeen, double now, bool evidence);
bool ASGAdCountdownEntry(bool adContext, double x, double y, double width, double height);
bool ASGVisualEvidenceMatches(const unsigned char *before, const unsigned char *after, unsigned length);
void ASGCancelSession(ASGSession *session);
#endif
