// One-shot SpringBoard-only diagnostic; never included in the shipping package.
// Runs the exact candidate controller in its authorized host, with no UI input.
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <dlfcn.h>

@interface NSObject (VPNHostProbe)
- (id)contentViewController;
- (id)vpn;
- (BOOL)ready;
- (BOOL)busy;
- (BOOL)connected;
- (NSString *)preferredProvider;
- (NSString *)activeProvider;
- (NSString *)message;
- (void)setStateChanged:(void (^)(void))block;
- (NSDictionary *)selectionIntent:(NSString *)provider;
- (void)applySelection:(NSDictionary *)intent;
- (void)toggle;
@end

static id Module, Controller;
static NSInteger Step;
static NSDate *Deadline;
static NSString *OriginalPreference;
static BOOL SeenBusy;
static void Log(NSString *line) {
    NSString *path = @"/var/mobile/Library/Caches/ayao.vpn-candidate-host.log";
    NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:path];
    if (!handle) { [[line stringByAppendingString:@"\n"] writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil]; return; }
    [handle seekToEndOfFile]; [handle writeData:[[line stringByAppendingString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding]];
    [handle closeFile];
}
static void Advance(void) {
    if (!Controller || Step < 0) return;
    if ([Controller busy]) { SeenBusy = YES; return; }
    if (Deadline.timeIntervalSinceNow <= 0) { Log(@"TIMEOUT=1"); Step = -1; return; }
    NSString *active = [Controller activeProvider];
    Log([NSString stringWithFormat:@"step=%ld ready=%d busy=%d connected=%d preferred=%@ active=%@ message=%@",
        (long)Step, [Controller ready], [Controller busy], [Controller connected], [Controller preferredProvider], active, [Controller message]]);
    if (![Controller ready]) return;
    if (Step == 0) {
        if (![active isEqual:@"none"]) { Log(@"REFUSED_INITIAL_ACTIVE=1"); Step = -1; return; }
        OriginalPreference = [Controller preferredProvider];
        Step = 1; [Controller applySelection:[Controller selectionIntent:@"easy"]]; return;
    }
    if (Step == 1 && [[Controller preferredProvider] isEqual:@"easy"]) {
        Step = 2; SeenBusy = NO; Deadline = [NSDate dateWithTimeIntervalSinceNow:45]; [Controller toggle]; return;
    }
    if (Step == 2) {
        if (!SeenBusy) return;
        if (![Controller connected] || ![active isEqual:@"easy"]) { Log(@"EASY_CONNECTION_FAILED=1"); Step = -1; return; }
        Log(@"EASY_CONNECTED=1"); Step = 3;
        [[NSURLSession.sharedSession dataTaskWithURL:[NSURL URLWithString:@"https://www.apple.com/library/test/success.html"]
            completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    NSString *body = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                    Log([NSString stringWithFormat:@"https=%ld success=%d error=%ld", (long)((NSHTTPURLResponse *)response).statusCode, [body containsString:@"Success"], (long)error.code]);
                    Step = 4; [Controller toggle];
                });
            }] resume]; return;
    }
    if (Step == 4 && [active isEqual:@"none"]) {
        Log(@"EASY_DISCONNECTED=1"); Step = 5;
        [Controller applySelection:[Controller selectionIntent:@"feilian"]]; return;
    }
    if (Step == 5 && [[Controller preferredProvider] isEqual:@"feilian"]) {
        Log(@"SELECTION_FEILIAN=1"); Step = 6;
        [Controller applySelection:[Controller selectionIntent:OriginalPreference]]; return;
    }
    if (Step == 6 && [[Controller preferredProvider] isEqual:OriginalPreference]) { Log(@"SELECTION_RESTORED=1\nHOST_SMOKE_DONE=1"); Step = -1; }
}
__attribute__((constructor)) static void Initialize(void) {
    if (![NSBundle.mainBundle.bundleIdentifier isEqual:@"com.apple.springboard"]) return;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 8 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        NSString *path = @"/var/jb/Library/ControlCenter/Bundles/FeilianControlCenter.bundle";
        NSBundle *bundle = [NSBundle bundleWithPath:path];
        if (!bundle) {
            Dl_info info = {0};
            if (dladdr((void *)Initialize, &info) && info.dli_fname) {
                NSString *root = @((const char *)info.dli_fname);
                for (NSUInteger level = 0; level < 4; level++) root = root.stringByDeletingLastPathComponent;
                path = [root stringByAppendingPathComponent:@"Library/ControlCenter/Bundles/FeilianControlCenter.bundle"];
                bundle = [NSBundle bundleWithPath:path];
            }
        }
        if (!bundle || ![bundle load]) { Log(@"HOST_BUNDLE_LOAD_FAILED=1"); return; }
        Module = [bundle.principalClass new]; Controller = [[Module contentViewController] vpn];
        Deadline = [NSDate dateWithTimeIntervalSinceNow:45];
        [Controller setStateChanged:^{ dispatch_async(dispatch_get_main_queue(), ^{ Advance(); }); }];
        Advance();
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 50 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            if (Step >= 0) { Log(@"HOST_SMOKE_INCOMPLETE=1"); Step = -1; }
        });
    });
}
