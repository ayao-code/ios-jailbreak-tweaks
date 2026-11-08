// macOS offline fixture check only: no UIKit, hit testing or real app actions.
#import <AppKit/AppKit.h>
#import <Vision/Vision.h>
#import "ASGMatchers.h"
#import "ASGPolicy.h"

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc < 2) return 2;
        NSMutableArray *output = [NSMutableArray array];
        for (int i = 1; i < argc; i++) {
            NSString *path = [NSString stringWithUTF8String:argv[i]];
            NSImage *source = [[NSImage alloc] initWithContentsOfFile:path];
            if (!source) return 3;
            CGFloat scale = MIN(1, MIN(960 / source.size.width, 1600 / source.size.height));
            NSImage *image = [[NSImage alloc] initWithSize:CGSizeMake(source.size.width * scale, source.size.height * scale)];
            [image lockFocus]; [source drawInRect:CGRectMake(0, 0, image.size.width, image.size.height)]; [image unlockFocus];
            CGImageRef bitmap = [image CGImageForProposedRect:NULL context:nil hints:nil];
            VNRecognizeTextRequest *request = [VNRecognizeTextRequest new];
            request.recognitionLevel = VNRequestTextRecognitionLevelAccurate;
            request.usesLanguageCorrection = NO;
            request.recognitionLanguages = @[@"zh-Hans", @"en-US"];
            NSError *error = nil;
            BOOL ok = [[[VNImageRequestHandler alloc] initWithCGImage:bitmap options:@{}] performRequests:@[request] error:&error];
            if (!ok || error) return 4;
            NSMutableArray *matches = [NSMutableArray array];
            for (VNRecognizedTextObservation *observation in request.results) {
                VNRecognizedText *text = [observation topCandidates:1].firstObject;
                ASGActionKind kind = ASGActionForOCRText(text.string);
                if (kind == ASGActionNone || text.confidence < .25 || ASGUnsafeActionText(text.string)) continue;
                CGRect b = observation.boundingBox;
                BOOL authorizedWithoutOverlay = kind == ASGActionAdCountdown
                    ? ASGAdCountdownEntry(false, b.origin.x, 1 - b.origin.y - b.size.height, b.size.width, b.size.height)
                    : ASGAuthorizeCandidate(kind == ASGActionSkip, ASGExplicitAdText(text.string),
                    ASGCountdownText(text.string), false, ASGArrowText(text.string), b.origin.x, 1 - b.origin.y - b.size.height, b.size.width, b.size.height);
                [matches addObject:@{@"text": text.string, @"confidence": @(text.confidence), @"kind": @(kind),
                    @"authorizedWithoutOverlay": @(authorizedWithoutOverlay)}];
            }
            [output addObject:@{@"file": path, @"matches": matches}];
        }
        NSData *json = [NSJSONSerialization dataWithJSONObject:output options:NSJSONWritingPrettyPrinted error:NULL];
        fwrite(json.bytes, 1, json.length, stdout); puts("");
    }
    return 0;
}
