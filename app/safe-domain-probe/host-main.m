#import <Foundation/Foundation.h>
#import "ProbeReport.h"

int main(int argumentCount, char *arguments[]) {
    @autoreleasepool {
        NSDictionary *report = SDPCollectReport(@"host_validation");
        NSError *error = nil;
        NSData *data = [NSJSONSerialization dataWithJSONObject:report
            options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys error:&error];
        if (!data) {
            fprintf(stderr, "report_serialization_failed\n");
            return 1;
        }
        fwrite(data.bytes, 1, data.length, stdout);
        fputc('\n', stdout);
        return 0;
    }
}
