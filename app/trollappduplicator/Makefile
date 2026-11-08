ARCHS = arm64

TARGET := iphone:clang:16.5:15.0
INSTALL_TARGET_PROCESSES = TrollAppDuplicator

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = TrollAppDuplicator

TrollAppDuplicator_FILES = thirdparty/SSZipArchive/minizip/unzip.c thirdparty/SSZipArchive/minizip/crypt.c thirdparty/SSZipArchive/minizip/ioapi_buf.c thirdparty/SSZipArchive/minizip/ioapi_mem.c thirdparty/SSZipArchive/minizip/ioapi.c thirdparty/SSZipArchive/minizip/minishared.c thirdparty/SSZipArchive/minizip/zip.c thirdparty/SSZipArchive/minizip/aes/aes_ni.c thirdparty/SSZipArchive/minizip/aes/aescrypt.c thirdparty/SSZipArchive/minizip/aes/aeskey.c thirdparty/SSZipArchive/minizip/aes/aestab.c thirdparty/SSZipArchive/minizip/aes/fileenc.c thirdparty/SSZipArchive/minizip/aes/hmac.c thirdparty/SSZipArchive/minizip/aes/prng.c thirdparty/SSZipArchive/minizip/aes/pwd2key.c thirdparty/SSZipArchive/minizip/aes/sha1.c thirdparty/SSZipArchive/SSZipArchive.m
TrollAppDuplicator_FILES += main.m AppDelegate.m AppList.m RootViewController.m AppDuplicator.m thirdparty/TDUtils.m thirdparty/LSApplicationProxy+AltList.m thirdparty/TDFileManagerViewController.m
TrollAppDuplicator_FILES += ClonePolicy.m CloneSettingsViewController.m MachOInspector.c GroupMigration.c IPAImport.m AppInputStatus.m
TrollAppDuplicator_FILES += tests/device_import_probe.m
TrollAppDuplicator_FRAMEWORKS = UIKit CoreGraphics MobileCoreServices UniformTypeIdentifiers
TrollAppDuplicator_CFLAGS = -fobjc-arc
ifeq ($(CLONE_VARIANT),upstream)
TrollAppDuplicator_CFLAGS += -DCLONE_UPSTREAM_EXPERIMENT=1
endif

include $(THEOS_MAKE_PATH)/application.mk

after-stage::
	ldid -Sentitlements.plist $(THEOS_STAGING_DIR)/Applications/TrollAppDuplicator.app/TrollAppDuplicator
	python3 scripts/package-tool.py "$(THEOS_STAGING_DIR)/Applications/TrollAppDuplicator.app" "$(CLONE_VARIANT)"
