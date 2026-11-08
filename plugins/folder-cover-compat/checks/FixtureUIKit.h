#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

// Renamed fake image types cannot collide with UIKit on the device. No UIKit
// linkage or screen/UI methods are used by the fixture.
#define UIImage FCFixtureImage
@interface FCFixtureImage : NSObject
@property(nonatomic) CGSize size;
@property(nonatomic) CGFloat scale;
@end
