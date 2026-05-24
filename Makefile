ARCHS = arm64 arm64e
TARGET := iphone:clang:16.5:16.0
THEOS_PACKAGE_SCHEME = rootless
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = DoubaoPowerButton DeepSeekVoiceHelper
DoubaoPowerButton_FILES = Tweak.xm
DoubaoPowerButton_CFLAGS = -fobjc-arc
DoubaoPowerButton_FRAMEWORKS = Foundation UIKit

DeepSeekVoiceHelper_FILES = DeepSeekVoiceHelper.xm
DeepSeekVoiceHelper_CFLAGS = -fobjc-arc
DeepSeekVoiceHelper_FRAMEWORKS = Foundation UIKit CoreGraphics

include $(THEOS_MAKE_PATH)/tweak.mk

SUBPROJECTS += Preferences
include $(THEOS_MAKE_PATH)/aggregate.mk
