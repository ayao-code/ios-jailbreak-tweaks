#ifndef AY_CAMERA_POLICY_H
#define AY_CAMERA_POLICY_H
#include <stdbool.h>
#ifdef __cplusplus
extern "C" {
#endif
typedef enum {
    AYCameraPassThrough,
    AYCameraLaunch,
    AYCameraConsumeRepeat
} AYCameraDecision;
// trigger: 0 side, 1 volume down. LastAccepted == 0 means no prior launch.
AYCameraDecision AYCameraDecide(bool enabled, unsigned configured, unsigned observed,
                               bool lockKnown, bool locked, bool lockedAllowed,
                               bool protectedAction, bool recording,
                               double now, double lastAccepted);
typedef struct {
    bool down, firstReleased, rejectedHold;
    double pressedAt, firstPressedAt, lastEventAt;
} AYVolumeDoublePress;
void AYVolumeDoublePressReset(AYVolumeDoublePress *state);
// All system volume events remain forwarded. Recognize on the second release.
bool AYVolumeDoublePressEvent(AYVolumeDoublePress *state, bool down, bool permitted, double now);
// A press observed locally stays protected until the native getter proves up.
bool AYVolumeSideBlocks(bool observedDown, bool nativeKnown, bool nativeDown);
bool AYCameraWakeMayActivate(bool sameRequest, bool samePreferences, bool permitted,
                             bool displayKnown, bool screenOn, bool lockKnown, bool locked);
#ifdef __cplusplus
}
#endif
#endif
