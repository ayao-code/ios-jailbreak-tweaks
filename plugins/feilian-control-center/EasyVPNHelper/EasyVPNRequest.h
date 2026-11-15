#import <Foundation/Foundation.h>
#import <notify.h>

static const char *const EasyRequestName = "ayao.easyvpn.native-request.v1";
static const char *const EasyResultName = "ayao.easyvpn.native-result.v1";
static const char *const EasyStageName = "ayao.easyvpn.native-stage.v1";
static const NSTimeInterval EasyLifetime = 30;
typedef NS_ENUM(uint8_t, EasyResult) {
    EasyConnected = 1, EasyDisconnected, EasyUnavailable, EasyLocked,
    EasyInteractionRequired, EasyFailed, EasyTimedOut
};
