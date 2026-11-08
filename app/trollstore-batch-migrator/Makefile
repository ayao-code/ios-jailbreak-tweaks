ARCHS = arm64 arm64e
TARGET := iphone:clang:latest:16.0

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = TrollStoreBatchMigrator

TrollStoreBatchMigrator_FILES = main.m AppDelegate.m ViewController.m BatchInstaller.m AMFIManager.m
TrollStoreBatchMigrator_FRAMEWORKS = UIKit
TrollStoreBatchMigrator_CFLAGS = -fobjc-arc -O2
TrollStoreBatchMigrator_CODESIGN_FLAGS = -Sentitlements.plist

include $(THEOS_MAKE_PATH)/application.mk

.PHONY: ipa
ipa: stage
	rm -rf build/Payload
	mkdir -p build/Payload
	cp -R .theos/_/Applications/TrollStoreBatchMigrator.app build/Payload/
	cd build && zip -qry TrollStoreBatchMigrator-1.1.2.ipa Payload
	rm -rf build/Payload
