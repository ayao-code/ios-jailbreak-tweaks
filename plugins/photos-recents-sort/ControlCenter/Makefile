ARCHS = arm64 arm64e
TARGET := iphone:clang:16.5:16.0
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = PhotosAlbumControlCenter
PhotosAlbumControlCenter_FILES = PhotosAlbumControlCenter.m
PhotosAlbumControlCenter_FRAMEWORKS = UIKit
PhotosAlbumControlCenter_PRIVATE_FRAMEWORKS = ControlCenterUIKit
PhotosAlbumControlCenter_INSTALL_PATH = /Library/ControlCenter/Bundles
PhotosAlbumControlCenter_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/bundle.mk
