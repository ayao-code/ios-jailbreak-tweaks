#import <Foundation/Foundation.h>
#import "ASGCache.h"
#include <assert.h>

static NSDictionary *Record(void) {
    return @{@"contextClass": @"SplashAd", @"controlClass": @"UIButton", @"identifier": @"skipAd",
             @"semantic": @"skip", @"path": @[@0], @"rect": @[@.8, @.05, @.1, @.05]};
}
static void Pump(double seconds) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:seconds];
    while (deadline.timeIntervalSinceNow > 0) {
        @autoreleasepool { [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.01]]; }
    }
}

int main(void) {
    @autoreleasepool {
        NSURL *directory = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString] isDirectory:YES];
        [NSFileManager.defaultManager createDirectoryAtURL:directory withIntermediateDirectories:YES attributes:nil error:NULL];
        NSURL *url = [directory URLByAppendingPathComponent:@"expired.plist"];
        NSMutableDictionary *expired = [Record() mutableCopy];
        expired[@"environment"] = @"env";
        expired[@"confirmedAt"] = @(NSDate.date.timeIntervalSince1970 - 8 * 86400);
        [@{@"schema": @1, @"records": @[expired]} writeToURL:url atomically:YES];
        ASGCache *cache = [[ASGCache alloc] initWithFileURL:url];
        [cache load]; Pump(.2);
        assert([cache recordsForEnvironment:@"env"].count == 0);
        [cache confirmRecord:Record() environment:@"env"];
        [cache confirmRecord:Record() environment:@"env"];
        assert([cache recordsForEnvironment:@"env"].count == 1); // Same locator can be relearned after expiry.
        Pump(.2);
        ASGCache *readback = [[ASGCache alloc] initWithFileURL:url]; [readback load]; Pump(.2);
        assert([readback recordsForEnvironment:@"env"].count == 1);

        NSURL *blocked = [directory URLByAppendingPathComponent:@"parent-is-a-file"];
        [@"block directory creation" writeToURL:blocked atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        NSURL *failedURL = [blocked URLByAppendingPathComponent:@"cache.plist"];
        ASGCache *recover = [[ASGCache alloc] initWithFileURL:failedURL];
        [recover confirmRecord:Record() environment:@"env"];
        [recover confirmRecord:Record() environment:@"env"];
        Pump(.2);
        assert(![NSFileManager.defaultManager fileExistsAtPath:failedURL.path]);
        [NSFileManager.defaultManager removeItemAtURL:blocked error:NULL]; // Only this generated test file.
        [recover confirmRecord:Record() environment:@"env"]; // Same content retries a dirty snapshot.
        Pump(.3);
        ASGCache *recovered = [[ASGCache alloc] initWithFileURL:failedURL]; [recovered load]; Pump(.2);
        assert([recovered recordsForEnvironment:@"env"].count == 1);
        [recover invalidateEnvironment:@"env"]; Pump(.2);
        ASGCache *deleted = [[ASGCache alloc] initWithFileURL:failedURL]; [deleted load]; Pump(.2);
        assert([deleted recordsForEnvironment:@"env"].count == 0);
        puts("PASS cache recovery: expired identical locator relearning, failed write identical-content retry, invalidation disk readback");
    }
    return 0;
}
