#import <Foundation/Foundation.h>
#import "AppDuplicator.h"
NSString *docPath(void) {
    NSString *p=NSProcessInfo.processInfo.environment[@"CLONE_FIXTURE_OUTPUT"];
    [NSFileManager.defaultManager createDirectoryAtPath:p withIntermediateDirectories:YES attributes:nil error:nil];
    return p;
}
int main(int argc,char **argv) {
    @autoreleasepool {
        if(argc!=3 && argc!=4) return 2;
        NSError *error=nil;
        NSDictionary *result=[[AppDuplicator new] createCloneFromURL:[NSURL fileURLWithPath:@(argv[1])]
             name:argc==4?@(argv[3]):@"测试分身" protectOriginal:atoi(argv[2])!=0 error:&error];
        NSDictionary *output=result?:@{@"error":error.localizedDescription?:@"unspecified"};
        NSData *data=[NSJSONSerialization dataWithJSONObject:output options:0 error:nil];
        fwrite(data.bytes,1,data.length,stdout); return result?0:1;
    }
}
