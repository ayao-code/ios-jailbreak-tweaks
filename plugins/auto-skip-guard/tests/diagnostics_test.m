#import <Foundation/Foundation.h>
#import "ASGDiagnostics.h"
#include <assert.h>

int main(void) {
    @autoreleasepool {
        NSString *stage = NSUUID.UUID.UUIDString;
        NSURL *cache = [NSFileManager.defaultManager URLsForDirectory:NSCachesDirectory inDomains:NSUserDomainMask].firstObject;
        NSURL *url = [[cache URLByAppendingPathComponent:@"ayao.AutoSkipGuard"] URLByAppendingPathComponent:@"diagnostics.json"];
        ASGStartDiagnosticCycle(10);
        for (unsigned i = 0; i < 80; i++) ASGDiagnostic(stage, @{@"index": @(i)});
        ASGFlushDiagnostics();
        ASGDiagnostic(@"after_flush_must_be_ignored", @{@"index": @100});
        ASGFlushDiagnostics();
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            NSData *data = [NSData dataWithContentsOfURL:url];
            NSDictionary *plist = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
            NSArray *events = plist[@"events"];
            assert(events.count == 64 && data.length <= 16384);
            assert([events.firstObject[@"stage"] isEqual:stage]);
            assert([events.lastObject[@"values"][@"index"] intValue] == 63);
            ASGStartDiagnosticCycle(11);
            for (unsigned i = 0; i < 80; i++) ASGDiagnostic(@"busy", @{@"index": @(i)});
            ASGDiagnostic(@"cancel", @{@"reason": @0});
            ASGFlushDiagnostics();
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 200 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
                NSDictionary *ended = [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfURL:url] options:0 error:NULL];
                assert([ended[@"events"] count] == 64);
                assert([[[ended[@"events"] lastObject][@"stage"] description] isEqual:@"cancel"]);
            });
            // The assertion above needs its own FIFO round before newer snapshots.
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 400 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
            ASGStartDiagnosticCycle(12);
            ASGDiagnostic(@"new_cycle", @{@"index": @1});
            ASGFlushDiagnostics();
            ASGStartDiagnosticCycle(12);
            ASGDiagnostic(@"cycle_12", @{@"index": @1});
            ASGFlushDiagnostics();
            ASGStartDiagnosticCycle(13);
            ASGDiagnostic(@"cycle_13", @{@"index": @1});
            ASGFlushDiagnostics();
            ASGStartDiagnosticCycle(14); // Bounded ring: retain latest cycle, not just first four.
            ASGDiagnostic(@"cycle_14", @{@"index": @1});
            ASGFlushDiagnostics();
            for (unsigned i = 15; i <= 1000; i++) {
                ASGStartDiagnosticCycle(i);
                ASGDiagnostic(@"latest", @{@"index": @(i)});
                ASGFlushDiagnostics();
            }
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                NSDictionary *current = [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfURL:url] options:0 error:NULL];
                assert([current[@"generation"] unsignedLongLongValue] == 1000);
                assert([current[@"events"] count] == 1);
                assert([current[@"events"][0][@"stage"] isEqual:@"latest"]);
                assert([current[@"events"][0][@"values"][@"index"] intValue] == 1000);
                assert([NSData dataWithContentsOfURL:url].length <= 16384);
                puts("PASS diagnostics: 64 events/cycle, 1000-cycle latest-only coalescing, <=16KB disk readback");
                exit(0);
            });
            });
        });
    }
    for (;;) {
        @autoreleasepool { [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]]; }
    }
}
