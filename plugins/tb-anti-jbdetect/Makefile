ARCHS = arm64 arm64e
TARGET = iphone:clang:16.5:15.0
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = TBAntiJBDetect

TBAntiJBDetect_FILES = Tweak.x
TBAntiJBDetect_CFLAGS = -fobjc-arc -Wno-deprecated-declarations
TBAntiJBDetect_FRAMEWORKS = Foundation UIKit

include $(THEOS_MAKE_PATH)/tweak.mk
