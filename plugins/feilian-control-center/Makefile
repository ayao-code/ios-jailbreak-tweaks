ARCHS = arm64 arm64e
TARGET := iphone:clang:16.5:16.0
THEOS_PACKAGE_SCHEME = rootless
include $(THEOS)/makefiles/common.mk
BUNDLE_NAME = FeilianControlCenter
FeilianControlCenter_FILES = FeilianControlCenter.m FeilianVPNController.m
FeilianControlCenter_FRAMEWORKS = UIKit Foundation
FeilianControlCenter_PRIVATE_FRAMEWORKS = ControlCenterUIKit
FeilianControlCenter_INSTALL_PATH = /Library/ControlCenter/Bundles
FeilianControlCenter_CFLAGS = -fobjc-arc -Wall -Wextra -Wno-unused-parameter
include $(THEOS_MAKE_PATH)/bundle.mk

TWEAK_NAME = FeilianConnectHelper
FeilianConnectHelper_FILES = FeilianConnectHelper.m
FeilianConnectHelper_FRAMEWORKS = Foundation UIKit
FeilianConnectHelper_LIBRARIES = substrate
FeilianConnectHelper_CFLAGS = -fobjc-arc -Wall -Wextra -Wno-unused-parameter
include $(THEOS_MAKE_PATH)/tweak.mk
