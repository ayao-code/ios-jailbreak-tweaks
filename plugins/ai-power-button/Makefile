ARCHS = arm64 arm64e
TARGET := iphone:clang:16.5:16.0
THEOS_PACKAGE_SCHEME = rootless
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = DoubaoPowerButton DoubaoAppVoiceHelper DeepSeekVoiceHelper
DoubaoPowerButton_FILES = Tweak.xm CameraShortcut.m CameraDiagnostics.m Shared/AYCameraPolicy.c
DoubaoPowerButton_CFLAGS = -fobjc-arc -DAYCAMERA_DIAGNOSTICS=$(or $(AYCAMERA_DIAGNOSTICS),0) -DAYVOLUME_DIAGNOSTICS=$(or $(AYVOLUME_DIAGNOSTICS),0)
DoubaoPowerButton_FRAMEWORKS = Foundation UIKit
DoubaoPowerButton_PRIVATE_FRAMEWORKS = SpringBoardServices

DoubaoAppVoiceHelper_FILES = DoubaoAppVoiceHelper.xm
DoubaoAppVoiceHelper_CFLAGS = -fobjc-arc
DoubaoAppVoiceHelper_FRAMEWORKS = Foundation UIKit CoreGraphics

DeepSeekVoiceHelper_FILES = DeepSeekVoiceHelper.xm
DeepSeekVoiceHelper_CFLAGS = -fobjc-arc
DeepSeekVoiceHelper_FRAMEWORKS = Foundation UIKit CoreGraphics

include $(THEOS_MAKE_PATH)/tweak.mk

SUBPROJECTS += Preferences
include $(THEOS_MAKE_PATH)/aggregate.mk
