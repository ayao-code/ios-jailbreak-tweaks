#import <Foundation/Foundation.h>
BOOL ASGSkipText(NSString *text);
BOOL ASGSkipIdentifier(NSString *identifier);
BOOL ASGAdClass(NSString *name);
BOOL ASGCountdownText(NSString *text);
NSString *ASGSkipMeaning(NSString *text);
typedef NS_ENUM(NSInteger, ASGActionKind) { ASGActionNone, ASGActionSkip, ASGActionCloseAd, ASGActionAdCountdown };
ASGActionKind ASGActionForText(NSString *text);
NSString *ASGMeaning(ASGActionKind kind);
// Discovery is deliberately broad. These helpers supply independent authorization evidence.
BOOL ASGUnsafeActionText(NSString *text);
BOOL ASGExplicitAdText(NSString *text);
BOOL ASGArrowText(NSString *text);
NSInteger ASGCountdownSeconds(NSString *text); // -1 means unknown, never assume zero.
NSString *ASGNormalizeText(NSString *text);
BOOL ASGAdCountdownText(NSString *text);
ASGActionKind ASGActionForOCRText(NSString *text);
unsigned ASGActionPriority(ASGActionKind kind);
