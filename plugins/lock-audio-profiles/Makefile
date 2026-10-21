ARCHS = arm64 arm64e
TARGET := iphone:clang:16.5:16.0
THEOS_PACKAGE_SCHEME = rootless

INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = LockAudioProfiles
LockAudioProfiles_FILES = Tweak.xm Shared/LAPShared.m
LockAudioProfiles_FRAMEWORKS = Foundation UIKit
LockAudioProfiles_PRIVATE_FRAMEWORKS = Celestial
LockAudioProfiles_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/tweak.mk

SUBPROJECTS += Preferences ControlCenter
include $(THEOS_MAKE_PATH)/aggregate.mk
