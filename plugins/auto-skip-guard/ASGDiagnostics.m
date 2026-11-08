#import "ASGDiagnostics.h"
#import <QuartzCore/QuartzCore.h>
#import "ASGPolicy.h"

#if ASG_DIAGNOSTICS
static NSMutableArray<NSDictionary *> *ASGEvents;
static BOOL ASGFlushed;
static uint64_t ASGDiagnosticGeneration;
static dispatch_queue_t ASGDiagnosticQueue;
static NSDictionary *ASGPendingSnapshot;
static BOOL ASGWriteInFlight;

static void ASGDrainDiagnosticWrite(void) {
    if (ASGWriteInFlight || !ASGPendingSnapshot) return;
    ASGWriteInFlight = YES;
    NSDictionary *snapshot = ASGPendingSnapshot;
    ASGPendingSnapshot = nil;
    dispatch_async(ASGDiagnosticQueue, ^{
        @autoreleasepool {
            NSData *data = [NSJSONSerialization dataWithJSONObject:snapshot options:0 error:NULL];
            if (data && data.length <= ASG_MAX_DIAGNOSTIC_BYTES) {
                NSURL *cache = [NSFileManager.defaultManager URLsForDirectory:NSCachesDirectory inDomains:NSUserDomainMask].firstObject;
                NSURL *directory = [cache URLByAppendingPathComponent:@"ayao.AutoSkipGuard" isDirectory:YES];
                [NSFileManager.defaultManager createDirectoryAtURL:directory withIntermediateDirectories:YES attributes:nil error:NULL];
                NSDataWritingOptions options = NSDataWritingAtomic;
#if TARGET_OS_IPHONE
                options |= NSDataWritingFileProtectionCompleteUntilFirstUserAuthentication;
#endif
                [data writeToURL:[directory URLByAppendingPathComponent:@"diagnostics.json"] options:options error:NULL];
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            ASGWriteInFlight = NO;
            ASGDrainDiagnosticWrite(); // One worker + at most the latest pending snapshot.
        });
    });
}
#endif

void ASGStartDiagnosticCycle(uint64_t generation) {
#if ASG_DIAGNOSTICS
    if (!NSThread.isMainThread) return;
    ASGDiagnosticGeneration = generation;
    ASGFlushed = NO;
    ASGEvents = [NSMutableArray arrayWithCapacity:64];
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        ASGDiagnosticQueue = dispatch_queue_create("ayao.autoskipguard.diagnostics", DISPATCH_QUEUE_SERIAL);
        dispatch_set_target_queue(ASGDiagnosticQueue, dispatch_get_global_queue(QOS_CLASS_UTILITY, 0));
    });
#else
    (void)generation;
#endif
}

void ASGRecordDiagnostic(NSString *stage, NSDictionary<NSString *, NSNumber *> *values) {
#if ASG_DIAGNOSTICS
    if (!NSThread.isMainThread || ASGFlushed || !stage.length || stage.length > 96 || values.count > 16) return;
    for (id key in values) if (![key isKindOfClass:NSString.class] || [key length] > 48
        || ![values[key] isKindOfClass:NSNumber.class]) return;
    if (!ASGEvents) ASGEvents = [NSMutableArray arrayWithCapacity:64];
    if (ASGEvents.count >= 64) {
        // Preserve the final lifecycle event instead of hiding expiry behind a full ring.
        if ([stage isEqual:@"cancel"]) [ASGEvents removeLastObject];
        else return;
    }
    // Only fixed stages, numeric metadata. Never store UI text, class names or accounts.
    [ASGEvents addObject:@{@"stage": stage, @"uptime": @(CACurrentMediaTime()), @"values": values ?: @{}}];
#else
    (void)stage; (void)values;
#endif
}

void ASGFlushDiagnostics(void) {
#if ASG_DIAGNOSTICS
    if (!NSThread.isMainThread || ASGFlushed || !ASGEvents.count) return;
    ASGFlushed = YES;
    ASGPendingSnapshot = @{@"schema": @1, @"generation": @(ASGDiagnosticGeneration), @"events": [ASGEvents copy]};
    ASGEvents = nil;
    if (!ASGDiagnosticQueue) ASGDiagnosticQueue = dispatch_queue_create("ayao.autoskipguard.diagnostics", DISPATCH_QUEUE_SERIAL);
    ASGDrainDiagnosticWrite();
#endif
}
