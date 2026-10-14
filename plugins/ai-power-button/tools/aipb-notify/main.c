#include <CoreFoundation/CoreFoundation.h>
#include <stdio.h>

int main(int argc, char *argv[]) {
    if (argc != 2) {
        fprintf(stderr, "usage: aipb-notify <darwin-notification-name>\n");
        return 64;
    }

    CFStringRef name = CFStringCreateWithCString(kCFAllocatorDefault, argv[1], kCFStringEncodingUTF8);
    if (!name) {
        fprintf(stderr, "invalid notification name\n");
        return 65;
    }

    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), name, NULL, NULL, true);
    CFRelease(name);
    return 0;
}
