#import <Foundation/Foundation.h>
#import "../FeilianVPNController.h"

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSString *action = argc == 2 ? @(argv[1]) : @"";
        if (![@[@"status", @"connect", @"disconnect"] containsObject:action]) {
            fprintf(stderr, "usage: feilian-vpn-test status|connect|disconnect\n");
            return 2;
        }
        FeilianVPNController *vpn = [FeilianVPNController new];
        __block BOOL requested = NO, finished = NO, failed = NO, sawBusy = NO;
        CFAbsoluteTime begin = CFAbsoluteTimeGetCurrent();
        vpn.operationFailed = ^(NSString *message) {
            fprintf(stderr, "operation_failed: %s\n", message.UTF8String);
            failed = YES;
            finished = YES;
        };
        __weak FeilianVPNController *weakVPN = vpn;
        // Initial profile enumeration can precede the asynchronous NE status.
        // Warm up only this bounded test process before choosing an action.
        NSDate *warmup = [NSDate dateWithTimeIntervalSinceNow:1];
        while (warmup.timeIntervalSinceNow > 0)
            [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
        vpn.stateChanged = ^{
            FeilianVPNController *current = weakVPN;
            printf("elapsed=%.3f available=%d selected=%d connected=%d busy=%d\n",
                CFAbsoluteTimeGetCurrent() - begin, current.available, current.selected, current.connected, current.busy);
            fflush(stdout);
            if ([action isEqualToString:@"status"]) { finished = YES; return; }
            if (!current.available) return;
            if (!requested) {
                requested = YES;
                BOOL desired = [action isEqualToString:@"connect"];
                if ((desired && current.connected) || (!desired && !current.selected)) { finished = YES; return; }
                CFAbsoluteTime callBegin = CFAbsoluteTimeGetCurrent();
                [current requestSelected:desired];
                printf("callback_return_ms=%.3f\n", (CFAbsoluteTimeGetCurrent() - callBegin) * 1000);
            } else if (current.busy) sawBusy = YES;
            else if (sawBusy) finished = YES;
        };
        vpn.stateChanged();
        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:20];
        while (!finished && deadline.timeIntervalSinceNow > 0)
            [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
        // A bounded CLI run-loop is test-only; the installed module has no poll.
        return finished && !failed ? 0 : 1;
    }
}
