#import <Foundation/Foundation.h>

@interface AppDuplicator : NSObject

// input is an IPA URL or installed .app bundle; no decryption or installation.
- (NSDictionary *)createCloneFromURL:(NSURL *)input name:(NSString *)name
                    protectOriginal:(BOOL)protect error:(NSError **)error;
// Original experiment entry point: do not sign or transform shared permissions.
- (NSDictionary *)createUpstreamCloneFromURL:(NSURL *)input name:(NSString *)name
                           disableCallbacks:(BOOL)disable error:(NSError **)error;
- (NSDictionary *)createUpstreamCloneFromURL:(NSURL *)input name:(NSString *)name
                           disableCallbacks:(BOOL)disable isolateSharedGroup:(BOOL)isolate error:(NSError **)error;
@end
