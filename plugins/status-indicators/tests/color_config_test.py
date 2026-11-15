#!/usr/bin/env python3
"""Exercise the real orientation-aware color resolver without UIKit."""
from pathlib import Path
import subprocess
import sys


def main():
    root = Path(__file__).resolve().parents[1]
    out = Path(sys.argv[1])
    out.mkdir(parents=True, exist_ok=True)
    source = (root / 'SIConfiguration.m').read_text()
    functions = source[source.index('UIColor *SIColorFromSettings('):
                       source.index('NSString *SISpeedText(')]
    runtime = (root / 'SIController.m').read_text()
    preview = (root / 'Preferences/SIPreviewController.m').read_text()
    assert 'SIColorForOrientation(_settings,color,landscape)' in runtime
    assert 'SIColorForOrientation(_settings,dark ? UIColor.whiteColor : UIColor.blackColor,landscape)' in preview
    harness = r'''
#import <Foundation/Foundation.h>
#include <assert.h>
#include <math.h>
@interface UIColor : NSObject
@property double red, green, blue;
+ (instancetype)whiteColor;
+ (instancetype)blackColor;
+ (instancetype)colorWithRed:(double)red green:(double)green blue:(double)blue alpha:(double)alpha;
@end
@implementation UIColor
+ (instancetype)colorWithRed:(double)red green:(double)green blue:(double)blue alpha:(double)alpha {
    (void)alpha; UIColor *v=[UIColor new];v.red=red;v.green=green;v.blue=blue;return v;
}
+ (instancetype)whiteColor { return [self colorWithRed:1 green:1 blue:1 alpha:1]; }
+ (instancetype)blackColor { return [self colorWithRed:0 green:0 blue:0 alpha:1]; }
@end
static BOOL SIConfigBool(NSDictionary *s, NSString *k, BOOL fallback) {
    id v=s[k];return [v isKindOfClass:NSNumber.class] ? [v boolValue] : fallback;
}
static double SIConfigNumber(NSDictionary *s, NSString *k, double fallback, double low, double high) {
    id v=s[k];double n=[v isKindOfClass:NSNumber.class] || [v isKindOfClass:NSString.class] ? [v doubleValue] : fallback;
    return isfinite(n) ? MIN(high,MAX(low,n)) : fallback;
}
UIColor *SIColorForOrientation(NSDictionary *, UIColor *, BOOL);
FUNCTIONS
static void Same(UIColor *a,UIColor *b) {
    assert(fabs(a.red-b.red)<1e-9 && fabs(a.green-b.green)<1e-9 && fabs(a.blue-b.blue)<1e-9);
}
int main(void) {
 @autoreleasepool {
    UIColor *system=[UIColor colorWithRed:.2 green:.4 blue:.6 alpha:1];
    for (NSUInteger mode=0;mode<4;mode++) {
        NSMutableDictionary *s=[@{@"colorMode":@(mode),@"customColor":@"#123456",
                                  @"colorModeLandscape":@1,@"customColorLandscape":@"#ABCDEF"} mutableCopy];
        UIColor *portrait=SIColorFromSettings(s,system);
        Same(SIColorForOrientation(s,system,NO),portrait);
        Same(SIColorForOrientation(s,system,YES),portrait); // Legacy configuration.
        s[@"separateLandscapeColor"]=@NO;
        Same(SIColorForOrientation(s,system,YES),portrait);
        s[@"separateLandscapeColor"]=@YES;
        for (NSUInteger landscapeMode=0;landscapeMode<4;landscapeMode++) {
            s[@"colorModeLandscape"]=@(landscapeMode);
            Same(SIColorForOrientation(s,system,NO),portrait);
            UIColor *expected=landscapeMode==0 ? system : landscapeMode==1 ? UIColor.whiteColor :
                landscapeMode==2 ? UIColor.blackColor : [UIColor colorWithRed:171/255.0 green:205/255.0 blue:239/255.0 alpha:1];
            Same(SIColorForOrientation(s,system,YES),expected);
        }
        [s removeObjectForKey:@"colorModeLandscape"];
        [s removeObjectForKey:@"customColorLandscape"];
        Same(SIColorForOrientation(s,system,YES),portrait); // Missing values inherit.
    }
    Same(SIColorForOrientation(@{@"separateLandscapeColor":@YES,@"colorModeLandscape":@3,
         @"customColorLandscape":@"not-hex"},system,YES),system);
    printf("PASS orientation colors: legacy/shared defaults, portrait preserved, four modes, inheritance, malformed color, runtime/preview parity\n");
 }
 return 0;
}
'''.replace('FUNCTIONS', functions)
    path = out / 'color-config-harness.m'
    path.write_text(harness)
    subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-Wall', '-Wextra', '-Werror',
                    '-fsanitize=address,undefined', '-framework', 'Foundation',
                    str(path), '-o', str(out / 'color-config-test')], check=True)
    subprocess.run([str(out / 'color-config-test')], check=True)


if __name__ == '__main__':
    main()
