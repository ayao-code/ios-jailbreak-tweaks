THEOS ?= $(HOME)/theos

.PHONY: all clean package

all:
	$(MAKE) -C CR3PreviewCompat THEOS=$(THEOS) FINALPACKAGE=1 clean all

package: all
	THEOS=$(THEOS) ./scripts/build-package.sh

clean:
	$(MAKE) -C CR3PreviewCompat THEOS=$(THEOS) clean
