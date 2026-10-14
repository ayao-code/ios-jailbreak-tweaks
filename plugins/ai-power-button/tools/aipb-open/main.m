#import <Foundation/Foundation.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import <unistd.h>

int main(int argc, char *argv[]) {
    @autoreleasepool {
        if (argc != 2) {
            fprintf(stderr, "usage: aipb-open <bundle-id>\n");
            return 64;
        }

        void *framework = dlopen("/System/Library/PrivateFrameworks/FrontBoardServices.framework/FrontBoardServices", RTLD_NOW);
        if (!framework) {
            fprintf(stderr, "failed to load FrontBoardServices: %s\n", dlerror());
            return 69;
        }

        Class serviceClass = objc_getClass("FBSOpenApplicationService");
        SEL serviceSelector = sel_registerName("serviceWithDefaultShellEndpoint");
        SEL openSelector = sel_registerName("openApplication:withOptions:completion:");
        if (!serviceClass || ![serviceClass respondsToSelector:serviceSelector]) {
            fprintf(stderr, "FBSOpenApplicationService unavailable\n");
            return 69;
        }

        id service = ((id (*)(id, SEL))objc_msgSend)(serviceClass, serviceSelector);
        if (![service respondsToSelector:openSelector]) {
            fprintf(stderr, "openApplication selector unavailable\n");
            return 69;
        }

        NSString *bundleIdentifier = [NSString stringWithUTF8String:argv[1]];
        ((void (*)(id, SEL, id, id, id))objc_msgSend)(service, openSelector, bundleIdentifier, nil, nil);
        usleep(500000);
        dlclose(framework);
        return 0;
    }
}
