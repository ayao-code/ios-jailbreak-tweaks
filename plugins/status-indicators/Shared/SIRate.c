#include "SIRate.h"
#include <math.h>
#include <string.h>
bool SIPhysicalInterface(const char *name) {
    if (!name) return false;
    if (!strcmp(name, "en0")) return true;
    if (strncmp(name, "pdp_ip", 6) || !name[6]) return false;
    for (const char *p = name + 6; *p; p++) if (*p < '0' || *p > '9') return false;
    return true;
}
SIRate SIUpdateRate(SIRateState *s, const SISample *samples, size_t count, double now) {
    SIRate rate = {0};
    if (!s || !samples || !isfinite(now) || count > SI_MAX_INTERFACES) {
        if (s) s->valid = false;
        return rate;
    }
    for (size_t i = 0; i < count; i++) {
        if (!memchr(samples[i].name, 0, SI_INTERFACE_NAME)) { s->valid = false; return rate; }
        for (size_t j = 0; j < i; j++) if (!strcmp(samples[i].name, samples[j].name)) { s->valid = false; return rate; }
    }
    double interval = now - s->time;
    if (s->valid && interval >= .5 && interval <= 10 && count && count == s->count) {
        rate.valid = true;
        for (size_t i = 0; i < count; i++) {
            bool matched = false;
            for (size_t j = 0; j < s->count; j++) {
                if (strcmp(samples[i].name, s->samples[j].name)) continue;
                matched = true;
                if (samples[i].received < s->samples[j].received || samples[i].sent < s->samples[j].sent) {
                    rate.valid = false; break;
                }
                rate.download += (double)(samples[i].received - s->samples[j].received) / interval;
                rate.upload += (double)(samples[i].sent - s->samples[j].sent) / interval;
                break;
            }
            if (!matched) rate.valid = false;
        }
    }
    // Invalid/partial differences are unknown, never measured zero; still rebaseline.
    if (!rate.valid) rate.download = rate.upload = 0;
    memcpy(s->samples, samples, count * sizeof(*samples));
    s->count = count; s->time = now; s->valid = true;
    return rate;
}
