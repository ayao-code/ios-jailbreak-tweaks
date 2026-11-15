#!/usr/bin/env python3
"""Compile preview's actual mode selection statements without UIKit or a device."""
from pathlib import Path
import re
import subprocess
import sys


def main():
    root = Path(__file__).resolve().parents[1]
    out = Path(sys.argv[1])
    out.mkdir(parents=True, exist_ok=True)
    source = (root / "Preferences/SIPreviewController.m").read_text()
    start = source.index("    NSInteger focusStyle=")
    end = source.index("    [_items renderVPN:", start)
    statements = source[start:end]
    mute = re.search(r"mute:(SIConfigBool\([^)]*\)) focus:", source)[1]
    harness = r'''
#import <Foundation/Foundation.h>
#include <assert.h>
#include <math.h>
static BOOL SIConfigBool(NSDictionary *s, NSString *key, BOOL fallback) {
    id v=s[key];return [v isKindOfClass:NSNumber.class] ? [v boolValue] : fallback;
}
static double SIConfigNumber(NSDictionary *s, NSString *key, double fallback, double low, double high) {
    id v=s[key];double n=[v respondsToSelector:@selector(doubleValue)] ? [v doubleValue] : fallback;
    return isfinite(n) ? MIN(high,MAX(low,n)) : fallback;
}
int main(void) {
    @autoreleasepool {
        unsigned count=0;
        for (unsigned enabled=0;enabled<2;enabled++) for (unsigned muteSetting=0;muteSetting<2;muteSetting++)
            for (unsigned requested=0;requested<=5;requested++) {
                NSDictionary *_settings=@{@"showFocus":@(enabled),@"showMute":@(muteSetting),@"focusStyle":@(requested)};
STATEMENTS
                BOOL mute=MUTE;
                assert(mute==muteSetting);
                assert(enabled ? [focus integerValue]==(requested ? requested-1 : 0) && focus.length : !focus.length);
                count++;
            }
        printf("PASS preview config: %u actual focus/mute selection combinations, no live status queries\n",count);
    }
}
'''.replace("STATEMENTS", statements).replace("MUTE", mute)
    path = out / "preview-config-harness.m"
    path.write_text(harness)
    subprocess.run(["xcrun", "clang", "-fobjc-arc", "-Wall", "-Wextra", "-Werror",
                    "-fsanitize=address,undefined", "-framework", "Foundation", str(path),
                    "-o", str(out / "preview-config-test")], check=True)
    subprocess.run([str(out / "preview-config-test")], check=True)


if __name__ == "__main__":
    main()
