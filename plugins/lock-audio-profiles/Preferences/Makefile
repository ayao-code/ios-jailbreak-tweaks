ARCHS = arm64 arm64e
TARGET := iphone:clang:16.5:16.0
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = LockAudioProfilesPrefs
LockAudioProfilesPrefs_FILES = LAPRootListController.m
LockAudioProfilesPrefs_FRAMEWORKS = UIKit
LockAudioProfilesPrefs_PRIVATE_FRAMEWORKS = Preferences
LockAudioProfilesPrefs_INSTALL_PATH = /Library/PreferenceBundles
LockAudioProfilesPrefs_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/bundle.mk
