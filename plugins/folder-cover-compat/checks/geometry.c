#include "CoverPolicy.h"
#include <assert.h>

int main(void) {
    assert(FCCoverSideForScreenHeight(2436) == 60);
    assert(FCCoverSideForScreenHeight(2796) == 64);
    assert(FCCoverSideForScreenHeight(2532) == 0);
    assert(FCNeedsRegeneration(45, 61, 3, 60));
    assert(!FCNeedsRegeneration(60, 60, 3, 60));
    assert(!FCNeedsRegeneration(0, 0, 3, 60));
    assert(!FCNeedsRegeneration(NAN, 61, 3, 60));
    return 0;
}
