#include "AYCameraPolicy.h"
#include <assert.h>
#include <stdio.h>

int main(void) {
    for(unsigned mask=0;mask<128;mask++) {
        bool allowed=AYCameraWakeMayActivate(mask&1,mask&2,mask&4,mask&8,mask&16,mask&32,mask&64);
        assert(allowed==(mask==127));
    }
    // Cancellation/timeout or preference generation replacement defeats ready.
    assert(!AYCameraWakeMayActivate(false,true,true,true,true,true,true));
    assert(!AYCameraWakeMayActivate(true,false,true,true,true,true,true));
    // Waking/unlocking is not permission to fall back to unrestricted Camera.
    assert(!AYCameraWakeMayActivate(true,true,true,true,true,true,false));
    assert(!AYCameraWakeMayActivate(true,true,true,true,false,true,true));
    assert(!AYCameraWakeMayActivate(true,true,true,false,true,true,true));
    puts("PASS camera wake activation: 128 gate combinations + cancellation/lock/display boundaries");
    return 0;
}
