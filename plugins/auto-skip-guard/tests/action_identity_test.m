#import "ASGActionIdentity.h"
#include <assert.h>
static NSDictionary *Callback(id target, NSString *action, unsigned event) {
    return @{@"target": target, @"action": action, @"event": @(event)};
}
int main(void) {
    @autoreleasepool {
        NSObject *a = [NSObject new], *b = [NSObject new];
        NSDictionary *close = Callback(a, @"close:", 64), *other = Callback(b, @"close:", 64);
        assert(ASGActionsEquivalent(@[close], @[close]));
        assert(!ASGActionsEquivalent(@[close], @[other]));
        assert(!ASGActionsEquivalent(@[close], @[Callback(a, @"purchase:", 64)]));
        assert(!ASGActionsEquivalent(@[close], @[Callback(a, @"close:", 8192)]));
        assert(!ASGActionsEquivalent(@[], @[]));
        assert(!ASGActionsEquivalent(@[close, close], @[close, other]));
        assert(ASGActionsEquivalent(@[close, other], @[other, close]));
        assert(!ASGActionsEquivalent(@[Callback(NSNull.null, @"close:", 64)], @[Callback(NSNull.null, @"close:", 64)]));
        puts("PASS action identity: target/selector/event equality, multiplicity, responder-chain rejection");
    }
}
