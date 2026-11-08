#ifndef AYAO_COVER_POLICY_H
#define AYAO_COVER_POLICY_H

#include <math.h>
#include <stdbool.h>

// Only the two screen sizes seen with the audited PrimalFolder2 0.1.2 build.
static inline double FCCoverSideForScreenHeight(double nativeHeight) {
    if (nativeHeight == 2436.0) return 60.0;
    if (nativeHeight == 2796.0) return 64.0;
    return 0.0;
}

static inline bool FCNeedsRegeneration(double width, double height,
                                      double scale, double side) {
    if (!isfinite(width) || !isfinite(height) || !isfinite(scale) ||
        width <= 0 || height <= 0 || scale <= 0 || side <= 0) return false;
    // Do not stretch a legitimately different image. The observed failure is
    // a non-square SBIconGridImage; a new image must be generated instead.
    return fabs(width - height) > 0.5 / scale;
}

#endif
