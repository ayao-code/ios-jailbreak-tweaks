#import <Foundation/Foundation.h>
#ifdef __cplusplus
extern "C" {
#endif
void AYCameraReloadPreferences(void);
id AYCameraPreferenceSnapshotValue(NSString *key);
void AYCameraRememberLockManager(id manager);
BOOL AYCameraHandleDoublePress(unsigned trigger, BOOL powerProtected, BOOL recording);
BOOL AYCameraShouldWaitForDoublePress(BOOL powerProtected, BOOL recording);
BOOL AYCameraVolumeDownEnabled(void);
void AYCameraDisplayDidAppear(id cover);
void AYCameraCancelPendingWake(void);
BOOL AYCameraPendingVolumeAllowed(void);
void AYCameraSetDisplayHooksReady(BOOL ready);
BOOL AYCameraHasPendingWake(void);
#ifdef __cplusplus
}
#endif
