ARCHS = arm64 arm64e
TARGET := iphone:clang:16.5:16.0
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = DoubaoPowerButtonPrefs
DoubaoPowerButtonPrefs_FILES = AYRootListController.m
DoubaoPowerButtonPrefs_FRAMEWORKS = UIKit
DoubaoPowerButtonPrefs_PRIVATE_FRAMEWORKS = Preferences
DoubaoPowerButtonPrefs_INSTALL_PATH = /Library/PreferenceBundles
DoubaoPowerButtonPrefs_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/bundle.mk
