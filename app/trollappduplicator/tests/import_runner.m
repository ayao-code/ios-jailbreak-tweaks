#import <Foundation/Foundation.h>
#import "IPAImport.h"
#include <stdlib.h>

#if CLONE_HOST_TEST
NSString *docPath(void) {
    NSString *path=NSProcessInfo.processInfo.environment[@"CLONE_FIXTURE_OUTPUT"];
    return path?:[NSTemporaryDirectory() stringByAppendingPathComponent:@"CloneStudioImportFixture"];
}
#endif

int main(int argc,char **argv) {
    @autoreleasepool {
        if(argc!=2) return 2;
        NSURL *source=[NSURL fileURLWithPath:@(argv[1])];
        cloneStageImport(source,^(NSURL *staged,NSError *error){
            NSDictionary *record=staged?@{@"path":staged.path,@"main_thread":@(NSThread.isMainThread)}:
                @{@"error":error.localizedDescription?:@"unknown",@"main_thread":@(NSThread.isMainThread)};
            NSData *json=[NSJSONSerialization dataWithJSONObject:record options:0 error:nil];
            fwrite(json.bytes,1,json.length,stdout);fflush(stdout);exit(staged?0:1);
        });
    }
    // Keep the real main thread alive so Foundation's main queue runs there.
    while(YES) {
        @autoreleasepool {
            [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
        }
    }
}
