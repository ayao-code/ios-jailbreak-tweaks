ARCHS = arm64 arm64e
TARGET := iphone:clang:latest:16.0
THEOS_PACKAGE_SCHEME = rootless

INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = AirPodsAutoNoise
AirPodsAutoNoise_FILES = Tweak.xm
AirPodsAutoNoise_FRAMEWORKS = Foundation UIKit
AirPodsAutoNoise_PRIVATE_FRAMEWORKS = MediaRemote
AirPodsAutoNoise_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/tweak.mk

SUBPROJECTS += Preferences
include $(THEOS_MAKE_PATH)/aggregate.mk
