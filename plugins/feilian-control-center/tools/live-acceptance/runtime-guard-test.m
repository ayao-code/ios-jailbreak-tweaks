// Host-side tests only. No device access or SpringBoard code injection.
#import <Foundation/Foundation.h>
#import "RuntimeGuard.h"

@interface AYATestController : NSObject
- (BOOL)ready;
- (void)reload;
- (int)wrongReady;
@end
@implementation AYATestController
- (BOOL)ready { return YES; }
- (void)reload { }
- (int)wrongReady { return 1; }
@end

int main(void) {
    @autoreleasepool {
        id object=[AYATestController new];
        NSString *path=@(class_getImageName([object class]));
        unsigned passed=0;
#define CHECK(expression) do { \
    if(!(expression)) { fprintf(stderr,"GUARD_CHECK_FAILED=%s\n",#expression); return 1; } \
    passed++; \
} while(0)
        CHECK(VPNTestObjectMatches(object,@"AYATestController",path));
        CHECK(!VPNTestObjectMatches(object,@"VPNController",path));
        CHECK(!VPNTestObjectMatches(object,@"AYATestController",@"/System/Library/NotOurImage"));
        CHECK(!VPNTestObjectMatches(nil,@"AYATestController",path));
        CHECK(!VPNTestObjectMatches(NSObject.new,@"AYATestController",path));
        CHECK(VPNTestSignature(object,@selector(ready),2,@encode(BOOL)));
        CHECK(VPNTestSignature(object,@selector(reload),2,"v"));
        CHECK(!VPNTestSignature(object,@selector(wrongReady),2,@encode(BOOL)));
        CHECK(!VPNTestSignature(object,@selector(ready),3,@encode(BOOL)));
        CHECK(!VPNTestSignature(object,NSSelectorFromString(@"missingSelector"),2,"v"));
        printf("RUNTIME_GUARD_CHECKS=%u PASS=1\n",passed);
        return 0;
    }
}
