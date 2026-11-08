SDK ?= $(HOME)/theos/sdks/iPhoneOS16.5.sdk
GUARD := ../../plugins/auto-skip-guard
GUARD_VERSION ?= 0.4.6
APP := dist/Payload/AutoSkipFixture.app
SOURCES := main.m $(GUARD)/AutoSkipGuard.m $(GUARD)/ASGMatchers.m $(GUARD)/ASGPolicy.c $(GUARD)/ASGCache.m $(GUARD)/ASGTouch.m $(GUARD)/ASGDiagnostics.m $(GUARD)/ASGTip.m $(GUARD)/ASGActionIdentity.m
.PHONY: all
all:
	mkdir -p $(APP)
	xcrun clang -target arm64-apple-ios15.0 -isysroot "$(SDK)" -Os -fobjc-arc -fblocks -Wall -Wextra -Werror -Wno-unused-parameter -DASG_TEST_HARNESS=1 -DASG_DIAGNOSTICS=1 -DASG_VERSION='@"0.4.0-fixture"' $(SOURCES) -framework UIKit -framework Foundation -framework CoreGraphics -framework QuartzCore -o $(APP)/AutoSkipFixture
	cp Info.plist $(APP)/Info.plist
	codesign --force --sign - $(APP)
	cd dist && zip -qr AutoSkipFixture_0.4.0.tipa Payload

original:
	mkdir -p dist-original/Payload/AutoSkipOriginalFixture.app/Frameworks
	xcrun clang -target arm64-apple-ios15.0 -isysroot "$(SDK)" -Os -fobjc-arc -fblocks -Wall -Wextra -Werror -Wno-unused-parameter -DASG_ORIGINAL_FIXTURE=1 main.m -framework UIKit -framework Foundation -o dist-original/Payload/AutoSkipOriginalFixture.app/AutoSkipOriginalFixture
	python3 tools/original-package.py
	codesign --force --sign - dist-original/Payload/AutoSkipOriginalFixture.app
	cd dist-original && zip -qr AutoSkipOriginalFixture.tipa Payload

payload:
	mkdir -p dist-payload/Payload/AutoSkipFixture.app/Frameworks
	xcrun clang -target arm64-apple-ios15.0 -isysroot "$(SDK)" -Os -fobjc-arc -fblocks -Wall -Wextra -Werror -Wno-unused-parameter -DASG_PAYLOAD_FIXTURE=1 main.m -framework UIKit -framework Foundation -o dist-payload/Payload/AutoSkipFixture.app/AutoSkipFixture
	cp Info.plist dist-payload/Payload/AutoSkipFixture.app/Info.plist
	cp $(GUARD)/dist/AutoSkipGuard_$(GUARD_VERSION)_arm64.dylib dist-payload/Payload/AutoSkipFixture.app/Frameworks/AutoSkipGuard.dylib
	codesign --force --sign - dist-payload/Payload/AutoSkipFixture.app
	cd dist-payload && zip -qr AutoSkipPayloadFixture.tipa Payload
