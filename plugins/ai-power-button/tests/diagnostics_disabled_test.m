#import "CameraDiagnostics.h"
#include <assert.h>
int main(void) {
    @autoreleasepool {
        int constructed=0;
        AYCameraDiagnostic(@"never",@{@"value":@(++constructed)});
        AYCameraAuditRuntime();
        assert(constructed==0);
        return 0;
    }
}
