#include "SINetworkSample.h"
#include <sys/types.h>
#include <sys/socket.h>
#include <sys/sysctl.h>
#include <net/if.h>
#include <stdlib.h>
#include <string.h>

/* Darwin routing ABI. The stripped iOS SDK omits net/route.h, but exposes
 * NET_RT_IFLIST2 and struct if_msghdr2 (including struct if_data64). */
#define SI_RTM_VERSION 5
#define SI_RTM_IFINFO2 0x12

bool SIReadNetworkSamples(SISample samples[SI_MAX_INTERFACES], size_t *count) {
    if (!samples || !count) return false;
    *count = 0;
    // One bounded transient allocation; no size probe/retry loop or retained history.
    unsigned char *buffer = malloc(SI_NETWORK_BUFFER_BYTES);
    if (!buffer) return false;
    size_t length = SI_NETWORK_BUFFER_BYTES;
    int mib[] = {CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0};
    bool valid = sysctl(mib, 6, buffer, &length, NULL, 0) == 0
        && length <= SI_NETWORK_BUFFER_BYTES;
    size_t offset = 0;
    while (valid && offset < length) {
        if (length - offset < 4) { valid = false; break; }
        uint16_t messageLength;
        memcpy(&messageLength, buffer + offset, sizeof(messageLength));
        if (messageLength < 4 || messageLength > length - offset) { valid = false; break; }
        if (buffer[offset + 2] != SI_RTM_VERSION) { valid = false; break; }
        if (buffer[offset + 3] == SI_RTM_IFINFO2) {
            if (messageLength < sizeof(struct if_msghdr2)) { valid = false; break; }
            struct if_msghdr2 message;
            memcpy(&message, buffer + offset, sizeof(message));
            char name[IFNAMSIZ] = {0};
            if ((message.ifm_flags & IFF_UP) && if_indextoname(message.ifm_index, name)
                && SIPhysicalInterface(name)) {
                if (*count >= SI_MAX_INTERFACES) { valid = false; break; }
                SISample *sample = &samples[(*count)++];
                memset(sample, 0, sizeof(*sample));
                memcpy(sample->name, name, strlen(name) + 1);
                sample->received = message.ifm_data.ifi_ibytes;
                sample->sent = message.ifm_data.ifi_obytes;
            }
        }
        offset += messageLength;
    }
    free(buffer);
    if (!valid) *count = 0;
    return valid;
}
