ARCHS = arm64 arm64e
TARGET := iphone:clang:latest:16.0
THEOS_PACKAGE_SCHEME = rootless

INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = LockLowPower
LockLowPower_FILES = Tweak.xm
LockLowPower_FRAMEWORKS = Foundation
LockLowPower_PRIVATE_FRAMEWORKS = LowPowerMode
LockLowPower_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/tweak.mk
