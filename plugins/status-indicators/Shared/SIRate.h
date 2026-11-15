#ifndef SI_RATE_H
#define SI_RATE_H
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#define SI_MAX_INTERFACES 32
#define SI_INTERFACE_NAME 32
typedef struct { char name[SI_INTERFACE_NAME]; uint64_t received, sent; } SISample;
typedef struct { SISample samples[SI_MAX_INTERFACES]; size_t count; double time; bool valid; } SIRateState;
typedef struct { double download, upload; bool valid; } SIRate;
SIRate SIUpdateRate(SIRateState *state, const SISample *samples, size_t count, double now);
bool SIPhysicalInterface(const char *name);
#endif
