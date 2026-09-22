ARCHS = arm64 arm64e
TARGET := iphone:clang:latest:16.0
THEOS_PACKAGE_SCHEME = rootless

INSTALL_TARGET_PROCESSES = SpringBoard oime_iOS KeyboardExtension

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = HideDoubaoPiP DoubaoNoJump
HideDoubaoPiP_FILES = Tweak.xm
HideDoubaoPiP_FRAMEWORKS = UIKit Foundation
HideDoubaoPiP_CFLAGS = -fobjc-arc

DoubaoNoJump_FILES = DoubaoNoJump.xm
DoubaoNoJump_FRAMEWORKS = UIKit Foundation AVFAudio
DoubaoNoJump_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/tweak.mk
