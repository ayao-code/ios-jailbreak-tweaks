#import <Foundation/Foundation.h>

NSDictionary *cloneInfoDictionary(NSDictionary *original, NSString *cloneID, NSString *name, BOOL protectOriginal);
NSDictionary *cloneEntitlements(NSDictionary *original, NSString *cloneID, BOOL protectOriginal);
