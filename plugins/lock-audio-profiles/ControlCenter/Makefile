ARCHS = arm64 arm64e
TARGET := iphone:clang:16.5:16.0
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = LockAudioProfilesCC
LockAudioProfilesCC_FILES = LockAudioProfilesCC.m ../Shared/LAPShared.m
LockAudioProfilesCC_FRAMEWORKS = UIKit
LockAudioProfilesCC_PRIVATE_FRAMEWORKS = ControlCenterUIKit
LockAudioProfilesCC_INSTALL_PATH = /Library/ControlCenter/Bundles
LockAudioProfilesCC_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/bundle.mk
