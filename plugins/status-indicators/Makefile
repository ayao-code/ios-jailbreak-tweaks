ARCHS = arm64 arm64e
TARGET := iphone:clang:16.5:16.0
THEOS_PACKAGE_SCHEME = rootless
INSTALL_TARGET_PROCESSES = SpringBoard
include $(THEOS)/makefiles/common.mk
TWEAK_NAME = StatusIndicators
StatusIndicators_FILES = Tweak.xm SIController.m SIFocusMonitor.m SIItemViews.m SIConfiguration.m SISettingsStore.m Shared/SIRate.c Shared/SINetworkSample.c Shared/SIPresentation.c
StatusIndicators_FRAMEWORKS = Foundation UIKit QuartzCore
StatusIndicators_CFLAGS = -fobjc-arc -Wall -Wextra -Werror -Wno-unused-parameter -DSI_DIAGNOSTICS=$(or $(SI_DIAGNOSTICS),0)
include $(THEOS_MAKE_PATH)/tweak.mk
SUBPROJECTS += Preferences
include $(THEOS_MAKE_PATH)/aggregate.mk
