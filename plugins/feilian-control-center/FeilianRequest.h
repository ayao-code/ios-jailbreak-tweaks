#import <Foundation/Foundation.h>
#import <notify.h>

// Versioned, short-lived request: no URL, session data or credentials.
static const char *const FeilianRequestName = "ayao.feiliancontrolcenter.silent-connect.v2";
static const char *const FeilianResultName = "ayao.feiliancontrolcenter.silent-result.v2";
static const NSTimeInterval FeilianRequestLifetime = 15;
typedef NS_ENUM(uint8_t, FeilianResult) {
    FeilianResultStarted = 1,
    FeilianResultUnavailable = 2,
    FeilianResultInteractionRequired = 3,
    FeilianResultTimedOut = 4,
    FeilianResultConnectionFailed = 5,
    FeilianResultNotBackground = 6,
};
