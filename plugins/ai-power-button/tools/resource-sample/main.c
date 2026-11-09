// Finite read-only whole-SpringBoard samples. No task port, attach, or hooks.
#include <sys/resource.h>
#include <sys/types.h>
#include <errno.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <time.h>
#include <unistd.h>
extern int proc_pidpath(int pid, void *buffer, uint32_t buffersize);
extern int proc_pid_rusage(int pid, int flavor, rusage_info_t *buffer);
static double monotonic(void) {
    struct timespec ts;
    if(clock_gettime(CLOCK_MONOTONIC,&ts))return 0;
    return ts.tv_sec+ts.tv_nsec/1e9;
}
int main(int argc,char **argv) {
    if(argc!=2)return 2;
    char *end;long target=strtol(argv[1],&end,10);
    if(*end || target<=0 || target>INT32_MAX)return 2;
    const char *expected="/System/Library/CoreServices/SpringBoard.app/SpringBoard";
    uint8_t identity[16]={0};uint64_t start=0;
    for(unsigned sample=0;sample<12;sample++) {
        char path[4096]={0};
        if(proc_pidpath((int)target,path,sizeof(path))<=0 || strcmp(path,expected))return 3;
        struct rusage_info_v2 data={0};
        if(proc_pid_rusage((int)target,RUSAGE_INFO_V2,(rusage_info_t *)&data)) {
            fprintf(stderr,"rusage_failed errno=%d\n",errno);return 4;
        }
        if(sample && (start!=data.ri_proc_start_abstime || memcmp(identity,data.ri_uuid,16)))return 5;
        if(!sample){start=data.ri_proc_start_abstime;memcpy(identity,data.ri_uuid,16);}
        printf("{\"sample\":%u,\"pid\":%ld,\"monotonic_seconds\":%.9f,\"user_time_ns\":%llu,\"system_time_ns\":%llu,\"resident_bytes\":%llu,\"footprint_bytes\":%llu,\"idle_wakeups\":%llu,\"disk_bytes_written\":%llu}\n",
            sample,target,monotonic(),(unsigned long long)data.ri_user_time,(unsigned long long)data.ri_system_time,
            (unsigned long long)data.ri_resident_size,(unsigned long long)data.ri_phys_footprint,
            (unsigned long long)data.ri_pkg_idle_wkups,(unsigned long long)data.ri_diskio_byteswritten);
        fflush(stdout);
        if(sample<11)sleep(3);
    }
    return 0;
}
