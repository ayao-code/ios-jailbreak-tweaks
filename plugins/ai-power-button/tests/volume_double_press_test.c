#include "AYCameraPolicy.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>

static bool tap(AYVolumeDoublePress *state,double time,bool permitted) {
    assert(!AYVolumeDoublePressEvent(state,true,permitted,time));
    return AYVolumeDoublePressEvent(state,false,permitted,time+.06);
}
int main(void) {
    AYVolumeDoublePress state={0};
    unsigned cases=0;
    for(unsigned first=0;first<2;first++)for(unsigned second=0;second<2;second++) {
        for(unsigned delay=0;delay<10;delay++) {
            AYVolumeDoublePressReset(&state);
            assert(!tap(&state,1,first));
            double secondTime=1.10+.05*delay;
            bool expected=first && second && secondTime+.06-1<=.45;
            assert(tap(&state,secondTime,second)==expected);cases++;
        }
    }
    AYVolumeDoublePressReset(&state);
    assert(!tap(&state,10,true));
    AYVolumeDoublePressReset(&state); // side/up/cancel/prefs/lock change
    assert(!tap(&state,10.2,true));
    assert(!AYVolumeDoublePressEvent(&state,true,true,10.3));
    assert(!AYVolumeDoublePressEvent(&state,false,true,10.6)); // long hold
    assert(!tap(&state,10.7,true));
    assert(tap(&state,10.9,true));
    assert(!tap(&state,11.1,true)); // third tap starts a new pair
    assert(!AYVolumeDoublePressEvent(&state,true,true,11.2));
    assert(!AYVolumeDoublePressEvent(&state,true,true,11.21)); // repeated down
    assert(!AYVolumeDoublePressEvent(&state,true,true,11.215));
    assert(!AYVolumeDoublePressEvent(&state,false,true,11.22));
    assert(!AYVolumeDoublePressEvent(&state,true,true,NAN));
    assert(!AYVolumeDoublePressEvent(&state,false,true,INFINITY));
    assert(!AYVolumeDoublePressEvent(&state,false,true,-1));
    assert(!tap(&state,12,true));
    assert(!AYVolumeDoublePressEvent(&state,true,true,11)); // time reversed
    assert(!AYVolumeDoublePressEvent(NULL,true,true,1));
    for(unsigned observed=0;observed<2;observed++)for(unsigned known=0;known<2;known++)
        for(unsigned down=0;down<2;down++)
            assert(AYVolumeSideBlocks(observed,known,down)==(observed && (!known || down)));
    // A side press without the final-up callback must stop blocking when the
    // native getter confirms release; while down/unknown it must still block.
    assert(AYVolumeSideBlocks(true,true,true));
    assert(AYVolumeSideBlocks(true,false,false));
    assert(!AYVolumeSideBlocks(true,true,false));
    AYVolumeDoublePressReset(&state);
    assert(!tap(&state,20,!AYVolumeSideBlocks(true,true,false)));
    assert(tap(&state,20.2,!AYVolumeSideBlocks(true,true,false)));
    printf("PASS volume double-press: %u option/timing cases + reset/hold/repeat/invalid-time boundaries\n",cases);
    return 0;
}
