ARCHS = arm64 arm64e
TARGET := iphone:clang:latest:16.0
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = CR3PreviewCompat
CR3PreviewCompat_FILES = Tweak.xm
CR3PreviewCompat_FRAMEWORKS = Foundation UIKit Photos ImageIO
CR3PreviewCompat_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/tweak.mk
