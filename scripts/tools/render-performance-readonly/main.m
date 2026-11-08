#import <Foundation/Foundation.h>
#import <mach/mach.h>
#import <dlfcn.h>
#import <time.h>
#import <unistd.h>

// iOS 16.3 implementation verified externally: x0 is a Mach port (0
// requests a temporary server port). It returns a created property list
// after CFDataCreate / CFPropertyListCreateWithData. No target app calls.
typedef CFPropertyListRef (*PerformanceInfoFunction)(mach_port_t);

static id Schema(id value, unsigned depth) {
    if (depth > 6) return @"depth_limit";
    if ([value isKindOfClass:NSDictionary.class]) {
        NSMutableDictionary *result = [NSMutableDictionary dictionary];
        unsigned count = 0;
        for (id key in value) {
            if (![key isKindOfClass:NSString.class] || ++count > 128) continue;
            result[key] = Schema(value[key], depth + 1);
        }
        return result;
    }
    if ([value isKindOfClass:NSArray.class]) {
        NSMutableArray *result = [NSMutableArray array];
        for (id element in value) {
            if (result.count >= 4) break;
            [result addObject:Schema(element, depth + 1)];
        }
        return result;
    }
    // Numeric metrics only; do not print app paths, account or text values.
    if ([value isKindOfClass:NSNumber.class]) return value;
    if ([value isKindOfClass:NSString.class]) return @"string_redacted";
    if ([value isKindOfClass:NSData.class]) return @"data_redacted";
    return @"other_redacted";
}

int main(int argc, char **argv) {
    @autoreleasepool {
        void *framework = dlopen("/System/Library/Frameworks/QuartzCore.framework/QuartzCore", RTLD_NOW);
        PerformanceInfoFunction info = framework ? dlsym(framework, "CARenderServerGetPerformanceInfo") : NULL;
        if (!info) { fprintf(stderr, "performance_info_unavailable\n"); return 69; }
        if (argc == 2 && (!strcmp(argv[1], "--display-stats") || !strcmp(argv[1], "--sample"))) {
            // Verified iOS 16.3: returns count; allocates char ** and each
            // description with malloc/asprintf. Counters are per display.
            unsigned (*stats)(mach_port_t, char ***) = dlsym(framework, "CARenderServerGetStatistics");
            if (!stats) return 69;
            BOOL sample = !strcmp(argv[1], "--sample");
            printf("meta low_power=%d thermal_state=%ld scope=lcd_compositor\n",
                NSProcessInfo.processInfo.lowPowerModeEnabled,
                (long)NSProcessInfo.processInfo.thermalState);
            for (unsigned iteration = 0; iteration < (sample ? 61u : 1u); iteration++) {
                char **rows = NULL;
                struct timespec timestamp;
                clock_gettime(CLOCK_MONOTONIC, &timestamp);
                unsigned count = stats(MACH_PORT_NULL, &rows);
                if (count > 16) { fprintf(stderr, "unexpected_display_count\n"); return 72; }
                BOOL found = NO;
                for (unsigned i = 0; i < count; i++) {
                    if (rows[i]) {
                        if (!sample) printf("%s", rows[i]);
                        else if (!strncmp(rows[i], "LCD display:", 12)) {
                            int frames, skipped, cloned, skippedCloned, nonDirty;
                            int parsed = sscanf(rows[i], "LCD display:\n\tTotal Frames:\t\t%d\n\tSkipped Frames:\t\t%d\n\tTotal Cloned Frames:\t%d\n\tSkipped Cloned Frames:\t%d\n\tNon-Dirty Frames:\t%d",
                                &frames, &skipped, &cloned, &skippedCloned, &nonDirty);
                            if (parsed == 5) {
                                printf("sample %.9f %d %d %d\n", timestamp.tv_sec + timestamp.tv_nsec / 1e9, frames, skipped, nonDirty);
                                found = YES;
                            }
                        }
                        free(rows[i]);
                    }
                }
                free(rows);
                if (!count || (sample && !found)) return 70;
                fflush(stdout);
                if (sample && iteration < 60) usleep(100000);
            }
            return 0;
        }
        if (argc != 1) return 64;
        CFPropertyListRef raw = info(MACH_PORT_NULL);
        if (!raw) { fprintf(stderr, "performance_info_empty\n"); return 70; }
        id value = CFBridgingRelease(raw);
        NSData *data = [NSJSONSerialization dataWithJSONObject:Schema(value, 0)
            options:NSJSONWritingSortedKeys | NSJSONWritingFragmentsAllowed error:nil];
        if (!data) return 71;
        fwrite(data.bytes, 1, data.length, stdout);
        fputc('\n', stdout);
        return 0;
    }
}
