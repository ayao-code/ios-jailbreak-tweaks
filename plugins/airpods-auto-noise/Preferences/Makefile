ARCHS = arm64 arm64e
TARGET := iphone:clang:16.5:16.0
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = AirPodsAutoNoisePrefs
AirPodsAutoNoisePrefs_FILES = AANRootListController.m
AirPodsAutoNoisePrefs_FRAMEWORKS = UIKit
AirPodsAutoNoisePrefs_PRIVATE_FRAMEWORKS = Preferences
AirPodsAutoNoisePrefs_INSTALL_PATH = /Library/PreferenceBundles
AirPodsAutoNoisePrefs_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/bundle.mk
