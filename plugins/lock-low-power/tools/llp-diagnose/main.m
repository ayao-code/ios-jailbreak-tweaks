#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <notify.h>

typedef void (*SBSAction)(void);

static int PrintState(void) {
    int token = NOTIFY_TOKEN_INVALID;
    uint32_t status = notify_register_check("com.apple.springboard.lockstate", &token);
    if (status != NOTIFY_STATUS_OK) {
        fprintf(stderr, "notify_register_check failed: %u\n", status);
        return 69;
    }

    uint64_t lockState = 0;
    status = notify_get_state(token, &lockState);
    notify_cancel(token);
    if (status != NOTIFY_STATUS_OK) {
        fprintf(stderr, "notify_get_state failed: %u\n", status);
        return 69;
    }

    printf("locked=%llu low_power=%d\n", lockState, NSProcessInfo.processInfo.lowPowerModeEnabled ? 1 : 0);
    return 0;
}

static int RunSpringBoardAction(const char *symbolName) {
    void *framework = dlopen(
        "/System/Library/PrivateFrameworks/SpringBoardServices.framework/SpringBoardServices",
        RTLD_NOW
    );
    if (!framework) {
        fprintf(stderr, "failed to load SpringBoardServices: %s\n", dlerror());
        return 69;
    }

    SBSAction action = (SBSAction)dlsym(framework, symbolName);
    if (!action) {
        fprintf(stderr, "missing symbol: %s\n", symbolName);
        dlclose(framework);
        return 69;
    }

    action();
    dlclose(framework);
    return 0;
}

int main(int argc, char *argv[]) {
    @autoreleasepool {
        if (argc != 2) {
            fprintf(stderr, "usage: llp-diagnose state|lock|wake\n");
            return 64;
        }

        NSString *command = [NSString stringWithUTF8String:argv[1]];
        if ([command isEqualToString:@"state"]) {
            return PrintState();
        }
        if ([command isEqualToString:@"lock"]) {
            return RunSpringBoardAction("SBSLockDevice");
        }
        if ([command isEqualToString:@"wake"]) {
            return RunSpringBoardAction("SBSUndimScreen");
        }

        fprintf(stderr, "unknown command: %s\n", argv[1]);
        return 64;
    }
}
