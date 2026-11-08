#import <Foundation/Foundation.h>
#import <mach/mach_time.h>
#import <unistd.h>
#import <stdint.h>
#import <sys/resource.h>
extern int proc_listallpids(void *, int);
extern int proc_pidpath(int, void *, uint32_t);
extern int proc_pidinfo(int, int, uint64_t, void *, int);
extern int proc_pid_rusage(int, int, rusage_info_t *);
struct ASGTaskInfo { uint64_t virtualSize, residentSize, totalUser, totalSystem, threadsUser, threadsSystem; int32_t counters[12]; };
int main(void) {
    @autoreleasepool {
        int pids[8192]; int n = proc_listallpids(pids, sizeof(pids));
        NSMutableArray *rows = [NSMutableArray array];
        for (int i = 0; i < n && i < 8192; i++) {
            char path[4096] = {0};
            if (proc_pidpath(pids[i], path, sizeof(path)) <= 0) continue;
            NSString *name = @(path);
            if (![name hasSuffix:@"/AutoSkipFixture.app/AutoSkipFixture"] && ![name hasSuffix:@"/AutoSkipOriginalFixture.app/AutoSkipOriginalFixture"]) continue;
            struct ASGTaskInfo info = {0};
            int bytes = proc_pidinfo(pids[i], 4, 0, &info, sizeof(info));
            struct rusage_info_v2 usage = {0};
            int usageResult = proc_pid_rusage(pids[i], RUSAGE_INFO_V2, (rusage_info_t *)&usage);
            [rows addObject:@{@"pid": @(pids[i]), @"path": name, @"read_bytes": @(bytes),
                              @"resident_bytes": @(info.residentSize), @"user_raw": @(info.totalUser),
                              @"system_raw": @(info.totalSystem), @"rusage_status": @(usageResult),
                              @"user_ns": @(usage.ri_user_time), @"system_ns": @(usage.ri_system_time),
                              @"phys_footprint": @(usage.ri_phys_footprint)}];
        }
        NSDictionary *result = @{@"operation": @"read_only_proc_info_no_attach", @"sample_uptime": @(NSProcessInfo.processInfo.systemUptime), @"processes": rows};
        NSData *json = [NSJSONSerialization dataWithJSONObject:result options:0 error:NULL];
        fwrite(json.bytes, 1, json.length, stdout); putchar('\n');
    }
    return 0;
}
