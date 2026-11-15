#include "SINetworkSample.h"
#include <stdio.h>
#include <time.h>
#include <unistd.h>
int main(void) {
    SIRateState state = {0};
    for (unsigned i = 0; i < 3; i++) {
        SISample samples[SI_MAX_INTERFACES] = {0};
        size_t count = 0;
        struct timespec now;
        if (!SIReadNetworkSamples(samples, &count) || clock_gettime(CLOCK_MONOTONIC, &now)) {
            puts("FAIL: bounded 64-bit interface snapshot unavailable"); return 1;
        }
        SIRate rate = SIUpdateRate(&state, samples, count, now.tv_sec + now.tv_nsec / 1e9);
        printf("sample=%u interfaces=%zu valid=%u download=%.0f upload=%.0f\n",
            i, count, rate.valid, rate.download, rate.upload);
        if (i < 2) sleep(2);
    }
    puts("PASS: finite three-sample read-only network probe");
    return 0;
}
