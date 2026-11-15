#ifndef SI_NETWORK_SAMPLE_H
#define SI_NETWORK_SAMPLE_H
#include "SIRate.h"
#define SI_NETWORK_BUFFER_BYTES (64 * 1024)
bool SIReadNetworkSamples(SISample samples[SI_MAX_INTERFACES], size_t *count);
#endif
