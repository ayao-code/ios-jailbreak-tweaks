#import <Foundation/Foundation.h>
#if AYCAMERA_DIAGNOSTICS
#ifdef __cplusplus
extern "C" {
#endif
void AYCameraDiagnostic(NSString *event, NSDictionary *details);
void AYCameraAuditRuntime(void);
#ifdef __cplusplus
}
#endif
#else
// Compile out both the call and its arguments in production. A no-op
// function still constructs NSDictionary/NSNumber arguments on button events.
#define AYCameraDiagnostic(...) do {} while (0)
#define AYCameraAuditRuntime() do {} while (0)
#endif
