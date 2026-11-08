#import <Foundation/Foundation.h>

// One-shot CLI probe in the signed tool, never attaches to or starts source apps.
int cloneRunImportProbe(NSString *path);
int cloneRunGroupGenerationProbe(NSString *path);
