#import "../SISettingsStore.h"
#import <Foundation/Foundation.h>
#include <time.h>
// Temporary finite tool; uses the EXACT Settings-bundle store, not a second writer.
// Call only for an authorized presentation test with both-end backup and restore.
int main(int argc, char **argv) {
    @autoreleasepool {
        if (argc!=2) return 64;
        NSData *input=[@(argv[1]) dataUsingEncoding:NSUTF8StringEncoding];
        if (!input) return 65;
        NSDictionary *changes=[NSJSONSerialization JSONObjectWithData:input options:0 error:NULL];
        NSSet *allowed=[NSSet setWithArray:@[@"speedArrangement",@"speedFont",@"speedX",@"speedY",@"speedHideZero"]];
        if (![changes isKindOfClass:NSDictionary.class] || !changes.count || changes.count>allowed.count) return 65;
        for (NSString *key in changes) if (![allowed containsObject:key] || ![changes[key] isKindOfClass:NSNumber.class]) return 65;
        struct timespec start,end; clock_gettime(CLOCK_MONOTONIC,&start);
        NSError *error=nil;
        BOOL saved=SIWriteSettings(changes,&error);
        clock_gettime(CLOCK_MONOTONIC,&end);
        NSDictionary *readback=SIReadSettings();
        BOOL match=YES; for (NSString *key in changes) match &= [readback[key] isEqual:changes[key]];
        NSDictionary *result=@{@"saved":@(saved),@"readbackMatches":@(match),
            @"elapsedMilliseconds":@((end.tv_sec-start.tv_sec)*1000+(end.tv_nsec-start.tv_nsec)/1e6),
            @"changes":changes,@"error":error.localizedDescription ?: @""};
        NSData *json=[NSJSONSerialization dataWithJSONObject:result options:0 error:NULL];
        fwrite(json.bytes,1,json.length,stdout);fputc('\n',stdout);
        return saved && match ? 0 : 1;
    }
}
