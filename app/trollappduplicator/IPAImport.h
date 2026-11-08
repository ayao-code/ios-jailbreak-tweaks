#import <Foundation/Foundation.h>

BOOL cloneCanImportURL(NSURL *url);
NSURL *cloneImportRoot(void);
// Copy only; never process the source URL in place. Completion runs on main queue.
void cloneStageImport(NSURL *url, void (^completion)(NSURL *, NSError *));
