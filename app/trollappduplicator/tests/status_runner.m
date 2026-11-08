#import <Foundation/Foundation.h>
#import "AppInputStatus.h"

int main(int argc, char **argv) {
    @autoreleasepool {
        if(argc!=2) return 2;
        NSString *status=cloneInstalledAppStatus(@(argv[1]));
        NSDictionary *result=@{@"status":status,@"selectable":@(cloneStatusAllowsSelection(status)),
            @"unknown_rejected":@(!cloneStatusAllowsSelection(@"unknown")),
            @"nil_rejected":@(!cloneStatusAllowsSelection(nil))};
        NSData *data=[NSJSONSerialization dataWithJSONObject:result options:0 error:nil];
        fwrite(data.bytes,1,data.length,stdout);
    }
    return 0;
}
