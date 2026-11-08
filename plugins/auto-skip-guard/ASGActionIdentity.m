#import "ASGActionIdentity.h"
static BOOL ASGCallbackValid(NSDictionary *c) {
    return [c isKindOfClass:NSDictionary.class] && c[@"target"] && c[@"target"] != NSNull.null
        && [c[@"action"] isKindOfClass:NSString.class] && [c[@"action"] length]
        && [c[@"event"] isKindOfClass:NSNumber.class];
}
BOOL ASGActionsEquivalent(NSArray<NSDictionary *> *left, NSArray<NSDictionary *> *right) {
    if (!left.count || left.count > 8 || left.count != right.count) return NO;
    BOOL used[8] = {NO};
    for (NSDictionary *a in left) {
        if (!ASGCallbackValid(a)) return NO;
        BOOL found = NO;
        for (NSUInteger i = 0; i < right.count; i++) {
            NSDictionary *b = right[i];
            if (!used[i] && ASGCallbackValid(b) && a[@"target"] == b[@"target"]
                && [a[@"action"] isEqual:b[@"action"]] && [a[@"event"] isEqual:b[@"event"]]) {
                used[i] = YES; found = YES; break;
            }
        }
        if (!found) return NO;
    }
    return YES;
}
