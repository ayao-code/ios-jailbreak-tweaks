#import <Foundation/Foundation.h>
NSDictionary *SIReadSettings(void);
BOOL SIWriteSettings(NSDictionary *changes, NSError **error);
#if SI_SETTINGS_TEST
void SISetTestSettingsPath(NSString *path);
#endif
