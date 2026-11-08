SDK ?= $(HOME)/theos/sdks/iPhoneOS16.5.sdk
CC := xcrun clang
VERSION ?= 0.4.6
DIAGNOSTICS ?= 0
OUTPUT := dist/AutoSkipGuard_$(VERSION)_arm64.dylib
SOURCES := AutoSkipGuard.m ASGCache.m ASGMatchers.m ASGTouch.m ASGDiagnostics.m ASGTip.m ASGPolicy.c ASGActionIdentity.m
CFLAGS := -target arm64-apple-ios15.0 -isysroot "$(SDK)" -Os -fobjc-arc -fblocks -Wall -Wextra -Werror -Wno-unused-parameter -DASG_DIAGNOSTICS=$(DIAGNOSTICS) -DASG_VERSION='@"$(VERSION)"'

.PHONY: all check clean
all: $(OUTPUT)

$(OUTPUT): $(SOURCES) ASGCache.h ASGPolicy.h ASGMatchers.h ASGTouch.h ASGDiagnostics.h ASGTip.h ASGActionIdentity.h
	mkdir -p dist
	$(CC) $(CFLAGS) -dynamiclib $(SOURCES) -framework Foundation -framework UIKit -framework CoreGraphics -framework QuartzCore -install_name @rpath/AutoSkipGuard.dylib -o "$@"
	codesign --force --sign - "$@"

check:
	./scripts/check.sh

clean:
	rm -f "$(OUTPUT)"
