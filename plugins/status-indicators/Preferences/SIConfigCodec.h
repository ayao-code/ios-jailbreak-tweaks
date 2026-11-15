#import <Foundation/Foundation.h>

NSArray<NSString *> *SIConfigKeys(void);
BOOL SIValidateConfigurationSettings(NSDictionary *settings, NSError **error);
// Pure encoding/validation: these functions never write preferences or post notifications.
NSData *SIExportConfiguration(NSDictionary *current, NSString *resourceDirectory, NSError **error);
NSDictionary *SIImportConfiguration(NSData *data, NSError **error);
// File input is bounded before plist decoding; imported picker files must be regular files.
NSData *SIReadConfigurationURL(NSURL *url, NSError **error);
