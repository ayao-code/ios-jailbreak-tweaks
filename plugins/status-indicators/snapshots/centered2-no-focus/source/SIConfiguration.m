#import "SIConfiguration.h"
#import "Shared/SIPresentation.h"
BOOL SIConfigBool(NSDictionary *settings, NSString *key, BOOL fallback) {
    id value = settings[key]; return [value isKindOfClass:NSNumber.class] ? [value boolValue] : fallback;
}
double SIConfigNumber(NSDictionary *settings, NSString *key, double fallback, double low, double high) {
    id value = settings[key];
    double number = [value isKindOfClass:NSNumber.class] || [value isKindOfClass:NSString.class] ? [value doubleValue] : fallback;
    return isfinite(number) ? MIN(high, MAX(low, number)) : fallback;
}
NSString *SIPositionKey(NSString *item, NSString *axis, BOOL landscape) {
    return [NSString stringWithFormat:@"%@%@%@", item, axis, landscape ? @"Landscape" : @""];
}
SIItemLayout SILayoutFromSettings(NSDictionary *s, BOOL landscape) {
    BOOL separate = landscape && SIConfigBool(s, @"separateLandscape", NO);
    // Missing landscape values inherit portrait rather than resetting users' layout.
    double (^position)(NSString *, NSString *, double, double, double) = ^double(NSString *item, NSString *axis, double fallback, double low, double high) {
        double portrait = SIConfigNumber(s, SIPositionKey(item, axis, NO), fallback, low, high);
        return separate ? SIConfigNumber(s, SIPositionKey(item, axis, YES), portrait, low, high) : portrait;
    };
    return (SIItemLayout){
        .vpnX=position(@"vpn", @"X", 25,0,100), .vpnY=position(@"vpn", @"Y",0,-25,100),
        .vpnSize=SIConfigBool(s,@"independentVPNSize",NO) ? SIConfigNumber(s,@"vpnSize",10,6,20) : SIConfigNumber(s,@"speedFont",10,6,20),
        .muteX=position(@"mute", @"X", 50,0,100), .muteY=position(@"mute", @"Y",25,-25,100),
        .muteSize=SIConfigNumber(s,@"muteSize",10,6,20),
        .speedX=position(@"speed",@"X",71,0,100), .speedY=position(@"speed",@"Y",0,-25,100),
        .speedFont=SIConfigNumber(s,@"speedFont",10,6,20),
        .centeredGroup=SIConfigBool(s,@"centeredGroup",NO),
        .groupGap=SIConfigNumber(s,@"groupGap",6,0,30),
        .speedGroupWidth=SIConfigNumber(s,@"speedGroupWidth",42,12,100)
    };
}
SIItemStyle SIStyleFromSettings(NSDictionary *s) {
    unsigned vpnStyle=(unsigned)SIConfigNumber(s,@"vpnStyle",0,0,3);
    // Preserve old text value 3; old half-shield value 2 becomes the new shield.
    if (vpnStyle==2) vpnStyle=1;
    return (SIItemStyle){.vpnStyle=vpnStyle,
        .weight=(unsigned)SIConfigNumber(s,@"fontWeight",1,0,2),
        .colorMode=(unsigned)SIConfigNumber(s,@"colorMode",0,0,3),
        .opacity=SIConfigNumber(s,@"opacity",1,.2,1)};
}
SISpeedStyle SISpeedStyleFromSettings(NSDictionary *s) {
    return (SISpeedStyle){.mode=(unsigned)SIConfigNumber(s,@"speedMode",0,0,2),
        .arrangement=(unsigned)SIConfigNumber(s,@"speedArrangement",0,0,1),
        .precision=(unsigned)SIConfigNumber(s,@"speedPrecision",0,0,2),
        .unitStyle=(unsigned)SIConfigNumber(s,@"speedUnitStyle",0,0,1),
        .units=SIConfigBool(s,@"speedShowUnit",NO), .arrows=SIConfigBool(s,@"speedArrows",NO),
        .uploadFirst=SIConfigBool(s,@"speedUploadFirst",NO), .hideZero=SIConfigBool(s,@"speedHideZero",NO),
        .zeroWhenInvalid=SIConfigBool(s,@"speedZeroWhenInvalid",NO),
        .arrowGap=SIConfigNumber(s,@"speedArrowGap",2,0,8),
        .unitGap=SIConfigNumber(s,@"speedUnitGap",1,0,8)};
}
UIColor *SIColorFromSettings(NSDictionary *s, UIColor *systemColor) {
    unsigned mode = (unsigned)SIConfigNumber(s,@"colorMode",0,0,3);
    if (mode==1) return UIColor.whiteColor;
    if (mode==2) return UIColor.blackColor;
    if (mode!=3) return systemColor;
    id value=s[@"customColor"];
    if (![value isKindOfClass:NSString.class]) return systemColor;
    NSString *hex=[value hasPrefix:@"#"] ? [value substringFromIndex:1] : value;
    if (hex.length!=6 || [hex rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdefABCDEF"].invertedSet].location!=NSNotFound) return systemColor;
    unsigned number=0; [[NSScanner scannerWithString:hex] scanHexInt:&number];
    return [UIColor colorWithRed:((number>>16)&255)/255.0 green:((number>>8)&255)/255.0 blue:(number&255)/255.0 alpha:1];
}
NSString *SISpeedText(double download, double upload, BOOL valid, SISpeedStyle style) {
    char buffer[96];
    SIComposeSpeed(download,upload,valid,style.mode,style.arrangement,style.units,style.arrows,
        style.uploadFirst,style.hideZero,style.zeroWhenInvalid,style.precision,style.unitStyle,buffer,sizeof(buffer));
    return @(buffer);
}
