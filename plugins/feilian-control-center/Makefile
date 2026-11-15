ARCHS = arm64 arm64e
TARGET := iphone:clang:16.5:16.0
THEOS_PACKAGE_SCHEME = rootless
include $(THEOS)/makefiles/common.mk
BUNDLE_NAME = FeilianControlCenter
FeilianControlCenter_FILES = FeilianControlCenter.m VPNController.m VPNModuleViewController.m Shared/VPNIPC.m
FeilianControlCenter_FRAMEWORKS = UIKit Foundation
FeilianControlCenter_PRIVATE_FRAMEWORKS = ControlCenterUIKit
FeilianControlCenter_INSTALL_PATH = /Library/ControlCenter/Bundles
FeilianControlCenter_CFLAGS = -fobjc-arc -Wall -Wextra -Wno-unused-parameter
include $(THEOS_MAKE_PATH)/bundle.mk

TWEAK_NAME = EasyVPNConnectionHelper FeilianConnectionHelper MultiVPNConnectionHelper
MultiVPNConnectionHelper_FILES = MultiVPNConnectionHelper.m Shared/VPNIPC.m
MultiVPNConnectionHelper_FRAMEWORKS = Foundation UIKit NetworkExtension
MultiVPNConnectionHelper_LIBRARIES = substrate
MultiVPNConnectionHelper_CFLAGS = -fobjc-arc -Wall -Wextra -Wno-unused-parameter -Wno-deprecated-declarations
EasyVPNConnectionHelper_FILES = EasyVPNConnectionHelper.m Shared/VPNIPC.m
EasyVPNConnectionHelper_FRAMEWORKS = Foundation UIKit NetworkExtension
EasyVPNConnectionHelper_LIBRARIES = substrate
EasyVPNConnectionHelper_CFLAGS = -fobjc-arc -Wall -Wextra -Wno-unused-parameter
FeilianConnectionHelper_FILES = FeilianConnectionHelper.m Shared/VPNIPC.m
FeilianConnectionHelper_FRAMEWORKS = Foundation UIKit NetworkExtension
FeilianConnectionHelper_LIBRARIES = substrate
FeilianConnectionHelper_CFLAGS = -fobjc-arc -Wall -Wextra -Wno-unused-parameter
include $(THEOS_MAKE_PATH)/tweak.mk
