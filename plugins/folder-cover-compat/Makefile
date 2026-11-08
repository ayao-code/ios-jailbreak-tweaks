THEOS ?= $(HOME)/theos
ARCHS = arm64e
TARGET := iphone:clang:16.5:16.3
THEOS_PACKAGE_SCHEME = roothide

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = zzFolderCoverCompat
zzFolderCoverCompat_FILES = Tweak.m
zzFolderCoverCompat_FRAMEWORKS = Foundation UIKit CoreGraphics
zzFolderCoverCompat_CFLAGS = -fno-objc-arc -Wall -Wextra -Werror

include $(THEOS_MAKE_PATH)/tweak.mk
