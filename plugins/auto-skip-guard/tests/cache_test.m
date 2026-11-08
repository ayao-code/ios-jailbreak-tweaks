#import <Foundation/Foundation.h>
#import "ASGCache.h"
#include <assert.h>

static NSDictionary *Record(NSString *name, double x) {
    return @{@"contextClass": @"ExampleSplashAdView", @"controlClass": @"UIButton",
             @"identifier": name, @"semantic": @"skip", @"path": @[@0],
             @"rect": @[@(x), @0.05, @0.1, @0.05]};
}

int main(void) {
    @autoreleasepool {
        NSURL *directory = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString] isDirectory:YES];
        NSURL *url = [directory URLByAppendingPathComponent:@"cache.plist"];
        dispatch_async(dispatch_get_main_queue(), ^{
            ASGCache *cache = [[ASGCache alloc] initWithFileURL:url];
            [cache load];
            [cache confirmRecord:Record(@"skip", .8) environment:@"env"];
            assert([cache recordsForEnvironment:@"env"].count == 0);
            [cache confirmRecord:Record(@"skip", .8) environment:@"env"];
            assert([cache recordsForEnvironment:@"env"].count == 1);
            [cache invalidateEnvironment:@"env"];
            assert([cache recordsForEnvironment:@"env"].count == 0);
            [cache confirmRecord:Record(@"changed", .7) environment:@"env"];
            assert([cache recordsForEnvironment:@"env"].count == 0);
            [cache confirmRecord:Record(@"changed", .8) environment:@"env"];
            assert([cache recordsForEnvironment:@"env"].count == 0); // Moved layout is a different confirmation.
            [cache confirmRecord:Record(@"changed", .8) environment:@"env"];
            assert([cache recordsForEnvironment:@"env"].count == 1);
            [cache confirmRecord:Record(@"bad", -.1) environment:@"invalid"];
            [cache confirmRecord:Record(@"bad", -.1) environment:@"invalid"];
            assert([cache recordsForEnvironment:@"invalid"].count == 0);
            NSMutableDictionary *adClose = [Record(@"close_ad", .4) mutableCopy];
            adClose[@"semantic"] = @"close_ad";
            [cache confirmRecord:adClose environment:@"env"];
            assert([cache recordsForEnvironment:@"env"].count == 1);
            [cache confirmRecord:adClose environment:@"env"];
            assert([cache recordsForEnvironment:@"env"].count == 2); // Skip and modal have independent identities.
            assert([cache recordsForEnvironment:@"new-version"].count == 0); // Never inherit a different version key.
            [cache invalidateEnvironment:@"env"];
            [cache confirmRecord:Record(@"replacement", .7) environment:@"env"];
            assert([cache recordsForEnvironment:@"env"].count == 0);
            [cache confirmRecord:Record(@"replacement", .7) environment:@"env"];
            assert([cache recordsForEnvironment:@"env"].count == 1);
            assert([[[cache recordsForEnvironment:@"env"] firstObject][@"identifier"] isEqual:@"replacement"]);
            // Start a disk load, then mutate before its main-queue completion can run.
            ASGCache *newCache = [[ASGCache alloc] initWithFileURL:url];
            [newCache load];
            [newCache invalidateEnvironment:@"env"];
            [newCache confirmRecord:Record(@"newest", .8) environment:@"new"];
            [newCache confirmRecord:Record(@"newest", .8) environment:@"new"];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                assert([newCache recordsForEnvironment:@"env"].count == 0);
                assert([newCache recordsForEnvironment:@"new"].count == 1);
                ASGCache *readback = [[ASGCache alloc] initWithFileURL:url];
                [readback load];
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                    assert([readback recordsForEnvironment:@"env"].count == 0);
                    assert([readback recordsForEnvironment:@"new"].count == 1);
                    puts("PASS cache: promotion, geometry consistency, invalidation, stale-load rejection, final disk readback");
                    exit(0);
                });
            });
        });
    }
    // A command-line dispatch_main may execute its main queue on a worker.
    // Pump the Cocoa main run loop so the same ownership assertions as iOS apply.
    for (;;) {
        @autoreleasepool {
            [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
        }
    }
}
