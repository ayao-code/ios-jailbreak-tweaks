ARCHS = arm64 arm64e
TARGET := iphone:clang:latest:16.0
THEOS_PACKAGE_SCHEME = rootless
INSTALL_TARGET_PROCESSES = CR3Companion

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = CR3Companion

LIBRAW_SOURCES = $(shell find vendor/LibRaw/src -type f -name '*.cpp' ! -name '*_ph.cpp' | sort)
CR3Companion_FILES = main.m AppDelegate.m ViewController.m CR3Processor.mm $(LIBRAW_SOURCES)
CR3Companion_FRAMEWORKS = UIKit Photos ImageIO CoreGraphics CoreLocation
CR3Companion_LIBRARIES = z
CR3Companion_CFLAGS = -fobjc-arc -Ivendor/LibRaw -DLIBRAW_NODLL -DLIBRAW_BUILDLIB -DLIBRAW_NOTHREADS -O2
CR3Companion_CCFLAGS = -std=c++11 -fexceptions -Wno-error=unused-variable -Wno-error=unused-but-set-variable -Wno-error=deprecated-declarations
CR3Companion_CODESIGN_FLAGS = -Sentitlements.plist

include $(THEOS_MAKE_PATH)/application.mk
