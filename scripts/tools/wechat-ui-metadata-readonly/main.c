#include <mach/mach.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <errno.h>
#include <limits.h>
#include <string.h>

extern int proc_pidpath(int, void *, uint32_t);
#define PROC_PIDPATHINFO_MAXSIZE 4096

extern kern_return_t mach_vm_read_overwrite(vm_map_t, mach_vm_address_t,
    mach_vm_size_t, mach_vm_address_t, mach_vm_size_t *);

int main(int argc, char **argv) {
    if (argc != 3) {
        fprintf(stderr, "usage: wechat-ui-metadata-readonly <WeChat-pid> <verified-global-address-hex>\n");
        return 64;
    }
    char *end = NULL;
    errno = 0;
    long pid = strtol(argv[1], &end, 10);
    if (errno || !*argv[1] || *end || pid <= 1 || pid > INT_MAX) return 64;
    errno = 0;
    int metadata_mode = strcmp(argv[2], "metadata") == 0;
    unsigned long long address = metadata_mode ? 0 : strtoull(argv[2], &end, 16);
    if (!metadata_mode && (errno || !*argv[2] || *end || address < 0x100000000ULL || address > UINT64_MAX - 5)) return 64;
    char path[PROC_PIDPATHINFO_MAXSIZE] = {0};
    if (proc_pidpath((pid_t)pid, path, sizeof(path)) <= 0) return 69;
    const char *name = strrchr(path, '/');
    if (!name || strcmp(name, "/WeChat") != 0 || !strstr(path, "/WeChat.app/WeChat")) return 77;
    mach_port_t task = MACH_PORT_NULL;
    kern_return_t kr = task_for_pid(mach_task_self(), (pid_t)pid, &task);
    if (kr != KERN_SUCCESS) {
        fprintf(stderr, "task-port read access refused: %d\n", kr);
        return 77;
    }
    if (metadata_mode) {
        // Parent follows only existing view/object and Mach-O metadata links.
        // No arbitrary heap search; hard bounds prevent an unbounded dump.
        puts("READY");
        fflush(stdout);
        unsigned char buffer[65536];
        unsigned int length;
        unsigned long long total = 0;
        unsigned int requests = 0;
        while (scanf("%llx %u", &address, &length) == 2) {
            if (!length || length > sizeof(buffer) || address < 0x100000000ULL ||
                address > UINT64_MAX - length || ++requests > 4000 ||
                (total += length) > 16 * 1024 * 1024) break;
            mach_vm_size_t count = 0;
            kr = mach_vm_read_overwrite(task, address, length,
                (mach_vm_address_t)buffer, &count);
            if (kr != KERN_SUCCESS || count != length) {
                printf("ERR %d\n", kr);
            } else {
                fputs("OK ", stdout);
                for (unsigned int i = 0; i < length; i++) printf("%02x", buffer[i]);
                putchar('\n');
            }
            fflush(stdout);
        }
        mach_port_deallocate(mach_task_self(), task);
        return 0;
    }
    uint8_t bytes[5] = {0};
    mach_vm_size_t count = 0;
    kr = mach_vm_read_overwrite(task, address, sizeof(bytes), (mach_vm_address_t)bytes, &count);
    mach_port_deallocate(mach_task_self(), task);
    if (kr != KERN_SUCCESS || count != sizeof(bytes)) {
        fprintf(stderr, "read failed: %d, bytes=%llu\n", kr, (unsigned long long)count);
        return 74;
    }
    printf("{\"pid\":%ld,\"address\":\"0x%llx\",\"bytes\":[%u,%u,%u,%u,%u]}\n",
        pid, address, bytes[0], bytes[1], bytes[2], bytes[3], bytes[4]);
    return 0;
}
