ARCHS = arm64
TARGET := iphone:clang:16.5:16.0
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

TOOL_NAME = lap-diagnose
lap-diagnose_FILES = main.m
lap-diagnose_FRAMEWORKS = Foundation
lap-diagnose_PRIVATE_FRAMEWORKS = Celestial
lap-diagnose_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/tool.mk
