#include "AYCameraPolicy.h"
#include <math.h>
#include <string.h>
bool AYVolumeSideBlocks(bool observedDown, bool nativeKnown, bool nativeDown) {
    return observedDown && (!nativeKnown || nativeDown);
}
bool AYCameraWakeMayActivate(bool sameRequest, bool samePreferences, bool permitted,
                             bool displayKnown, bool screenOn, bool lockKnown, bool locked) {
    return sameRequest && samePreferences && permitted && displayKnown && screenOn && lockKnown && locked;
}
void AYVolumeDoublePressReset(AYVolumeDoublePress *state) {
    if(state)memset(state,0,sizeof(*state));
}
bool AYVolumeDoublePressEvent(AYVolumeDoublePress *state, bool down, bool permitted, double now) {
    if(!state)return false;
    if(!permitted || !isfinite(now) || now<=0 || now<state->lastEventAt) {
        AYVolumeDoublePressReset(state);return false;
    }
    state->lastEventAt=now;
    if(down) {
        if(state->down) {state->firstReleased=false;state->rejectedHold=true;return false;}
        if(state->firstReleased && now-state->firstPressedAt>.45)state->firstReleased=false;
        state->down=true;state->pressedAt=now;return false;
    }
    if(!state->down)return false;
    state->down=false;
    if(state->rejectedHold || now-state->pressedAt>.25) {AYVolumeDoublePressReset(state);return false;}
    if(state->firstReleased && now-state->firstPressedAt<=.45) {
        AYVolumeDoublePressReset(state);return true;
    }
    state->firstReleased=true;state->firstPressedAt=state->pressedAt;return false;
}
AYCameraDecision AYCameraDecide(bool enabled, unsigned configured, unsigned observed,
                               bool lockKnown, bool locked, bool lockedAllowed,
                               bool protectedAction, bool recording,
                               double now, double lastAccepted) {
    if (!enabled || configured > 1 || configured != observed || !lockKnown
        || (locked && !lockedAllowed) || protectedAction || recording
        || !isfinite(now) || now <= 0 || !isfinite(lastAccepted) || lastAccepted < 0
        || now < lastAccepted) return AYCameraPassThrough;
    if (lastAccepted > 0 && now - lastAccepted < .7) return AYCameraConsumeRepeat;
    return AYCameraLaunch;
}
