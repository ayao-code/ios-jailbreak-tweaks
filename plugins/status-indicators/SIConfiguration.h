#import <UIKit/UIKit.h>
#ifndef SI_CONFIGURATION_H
#define SI_CONFIGURATION_H
typedef struct {
    double vpnX, vpnY, vpnSize;
    double muteX, muteY, muteSize;
    double focusX, focusY, focusSize;
    BOOL focusText;
    NSString *focusLabel;
    double speedX, speedY, speedFont;
    BOOL centeredGroup;
    double groupGap, speedGroupWidth;
} SIItemLayout;
typedef struct {
    unsigned vpnStyle, focusStyle, weight, colorMode;
    double opacity;
} SIItemStyle;
typedef struct {
    unsigned mode, arrangement, precision, unitStyle;
    BOOL units, arrows, uploadFirst, hideZero, zeroWhenInvalid;
    double arrowGap, unitGap;
} SISpeedStyle;
BOOL SIConfigBool(NSDictionary *settings, NSString *key, BOOL fallback);
double SIConfigNumber(NSDictionary *settings, NSString *key, double fallback, double low, double high);
SIItemLayout SILayoutFromSettings(NSDictionary *settings, BOOL landscape);
SIItemStyle SIStyleFromSettings(NSDictionary *settings);
SISpeedStyle SISpeedStyleFromSettings(NSDictionary *settings);
UIColor *SIColorFromSettings(NSDictionary *settings, UIColor *systemColor);
UIColor *SIColorForOrientation(NSDictionary *settings, UIColor *systemColor, BOOL landscape);
NSString *SISpeedText(double download, double upload, BOOL valid, SISpeedStyle style);
NSString *SIPositionKey(NSString *item, NSString *axis, BOOL landscape);
#endif
