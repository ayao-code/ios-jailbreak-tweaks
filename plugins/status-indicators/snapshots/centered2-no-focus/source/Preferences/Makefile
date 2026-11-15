ARCHS = arm64 arm64e
TARGET := iphone:clang:16.5:16.0
THEOS_PACKAGE_SCHEME = rootless
include $(THEOS)/makefiles/common.mk
BUNDLE_NAME = StatusIndicatorsPrefs
StatusIndicatorsPrefs_FILES = SIRootListController.m SIPreviewController.m ../SIItemViews.m ../SIConfiguration.m ../SISettingsStore.m ../Shared/SIPresentation.c
StatusIndicatorsPrefs_FRAMEWORKS = Foundation UIKit
StatusIndicatorsPrefs_PRIVATE_FRAMEWORKS = Preferences
StatusIndicatorsPrefs_INSTALL_PATH = /Library/PreferenceBundles
StatusIndicatorsPrefs_CFLAGS = -fobjc-arc
include $(THEOS_MAKE_PATH)/bundle.mk
