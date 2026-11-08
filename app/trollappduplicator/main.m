#import <Foundation/Foundation.h>
#import "AppDelegate.h"
#import "tests/device_import_probe.h"

int main(int argc, char *argv[]) {
    @autoreleasepool {
        if(argc==3 && !strcmp(argv[1],"--import-check")) return cloneRunImportProbe(@(argv[2]));
        if(argc==3 && !strcmp(argv[1],"--group-generation-check")) return cloneRunGroupGenerationProbe(@(argv[2]));
        return UIApplicationMain(argc, argv, nil, NSStringFromClass(AppDelegate.class));
    }
}
