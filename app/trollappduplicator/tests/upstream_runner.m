#import <Foundation/Foundation.h>
#import "AppDuplicator.h"
NSString *docPath(void) {
    NSString *path=NSProcessInfo.processInfo.environment[@"CLONE_FIXTURE_OUTPUT"];
    [NSFileManager.defaultManager createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:nil];
    return path;
}
int main(int argc, char **argv) {
    @autoreleasepool {
        if(argc<3 || argc>6) return 2;
        NSError *error=nil;
        if(argc==6) {
            // Regression seed: generation must ignore this legacy mapping.
            NSString *sourceID=@"cn.damai.iphone";
            NSUserDefaults *defaults=[[NSUserDefaults alloc] initWithSuiteName:@"CloneStudioHostFixture"];
            [defaults setObject:@(argv[5]) forKey:[@"clone.upstream.identity." stringByAppendingString:sourceID]];
        }
        NSDictionary *result=[[AppDuplicator new] createUpstreamCloneFromURL:[NSURL fileURLWithPath:@(argv[1])]
            name:argc>=4?@(argv[3]):@"Upstream Trial" disableCallbacks:atoi(argv[2])!=0
            isolateSharedGroup:argc>=5 && atoi(argv[4])!=0 error:&error];
        NSData *data=[NSJSONSerialization dataWithJSONObject:result?:@{@"error":error.localizedDescription?:@"unknown"} options:0 error:nil];
        fwrite(data.bytes,1,data.length,stdout);
        return result?0:1;
    }
}
