#import <Foundation/Foundation.h>
#import "../SISettingsStore.h"
#import "../SIConfiguration.h"
#include <sys/sysctl.h>

// One-shot native settings-store client, never an App launcher or a daemon.
// The caller must make verified local/device backups before --white.
int main(int argc, const char **argv) {
    @autoreleasepool {
        if (argc!=2 || getuid()!=501) return 2;
        BOOL apply=!strcmp(argv[1],"--white");
        if (!apply && strcmp(argv[1],"--read")) return 2;
        char machine[64]={0}; size_t length=sizeof(machine);
        if (sysctlbyname("hw.machine",machine,&length,NULL,0) || strcmp(machine,"iPhone13,1")) return 2;
        NSError *error=nil;
        if (apply && !SIWriteSettings(@{@"separateLandscapeColor":@YES,@"colorModeLandscape":@1},&error)) {
            fprintf(stderr,"%s\n",error.localizedDescription.UTF8String ?: "settings not saved");
            return 1;
        }
        NSDictionary *settings=SIReadSettings();
        NSMutableDictionary *values=[NSMutableDictionary dictionary];
        for (NSString *key in @[@"colorMode",@"customColor",@"separateLandscapeColor",@"colorModeLandscape",@"customColorLandscape",@"centeredGroup"])
            if (settings[key]) values[key]=settings[key];
        NSMutableArray *colors=[NSMutableArray array];
        for (NSNumber *landscape in @[@NO,@YES]) {
            UIColor *color=SIColorForOrientation(settings,UIColor.blackColor,landscape.boolValue);
            CGFloat red=0,green=0,blue=0,alpha=0;
            if (![color getRed:&red green:&green blue:&blue alpha:&alpha]) return 1;
            [colors addObject:@{@"landscape":landscape,@"red":@(red),@"green":@(green),@"blue":@(blue),@"alpha":@(alpha)}];
        }
        NSData *json=[NSJSONSerialization dataWithJSONObject:@{@"saved":@(apply),@"values":values,@"effective_colors_with_black_system_input":colors}
                                                   options:NSJSONWritingPrettyPrinted error:nil];
        return json && fwrite(json.bytes,1,json.length,stdout)==json.length ? 0 : 1;
    }
}
