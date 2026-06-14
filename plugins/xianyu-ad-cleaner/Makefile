ARCHS = arm64 arm64e
TARGET := iphone:clang:latest:16.0
THEOS_PACKAGE_SCHEME = rootless

INSTALL_TARGET_PROCESSES = FleaMarket

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = XianYuAdCleaner
XianYuAdCleaner_FILES = Tweak.xm
XianYuAdCleaner_FRAMEWORKS = UIKit Foundation
XianYuAdCleaner_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/tweak.mk
