#include "AYCameraPolicy.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>

int main(void) {
    unsigned cases = 0;
    const double last[] = {0, 9, 9.5, 10, 11, -1, NAN, INFINITY};
    // Exhaust every gate and exercise both launch and repeat with the actual runtime policy.
    for (unsigned mask = 0; mask < 128; mask++) {
        bool enabled = mask & 1, known = mask & 2, locked = mask & 4;
        bool allowed = mask & 8, protectedAction = mask & 16, recording = mask & 32;
        double now = mask & 64 ? NAN : 10;
        for (unsigned configured = 0; configured < 3; configured++) {
            for (unsigned observed = 0; observed < 3; observed++) {
                for (unsigned i = 0; i < sizeof(last) / sizeof(last[0]); i++) {
                    bool safe = enabled && known && (!locked || allowed)
                        && !protectedAction && !recording && configured < 2
                        && configured == observed && isfinite(now)
                        && isfinite(last[i]) && last[i] >= 0 && now >= last[i];
                    AYCameraDecision expected = !safe ? AYCameraPassThrough
                        : (last[i] > 0 && now - last[i] < .7 ? AYCameraConsumeRepeat : AYCameraLaunch);
                    assert(AYCameraDecide(enabled, configured, observed, known, locked,
                        allowed, protectedAction, recording, now, last[i]) == expected);
                    cases++;
                }
            }
        }
    }
    assert(AYCameraDecide(true,0,0,true,false,false,false,false,.1,0) == AYCameraLaunch);
    assert(AYCameraDecide(true,0,0,true,false,false,false,false,0,0) == AYCameraPassThrough);
    assert(AYCameraDecide(true,0,0,true,false,false,false,false,10.699,10) == AYCameraConsumeRepeat);
    assert(AYCameraDecide(true,0,0,true,false,false,false,false,10.701,10) == AYCameraLaunch);
    // Disabling/locking/protecting the gesture wins even during repeat suppression.
    assert(AYCameraDecide(false,0,0,true,false,false,false,false,10.1,10) == AYCameraPassThrough);
    assert(AYCameraDecide(true,0,0,true,true,false,false,false,10.1,10) == AYCameraPassThrough);
    assert(AYCameraDecide(true,0,0,true,false,false,true,false,10.1,10) == AYCameraPassThrough);
    assert(AYCameraDecide(true,0,0,true,false,false,false,true,10.1,10) == AYCameraPassThrough);
    printf("PASS camera runtime policy: %u matrix cases + 8 boundary/precedence cases\n", cases);
    return 0;
}
