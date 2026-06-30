ifndef THEOS
$(error THEOS is not set. Install Theos and export THEOS=/path/to/theos before building.)
endif

TARGET := iphone:clang:16.5:15.0

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = InsulationPrefs

InsulationPrefs_FILES = $(shell find Sources/InsulationPrefsObjC -type f \( -name '*.m' -o -name '*.c' -o -name '*.mm' -o -name '*.cpp' \)) \
$(shell find Sources/InsulationPrefsC -type f \( -name '*.m' -o -name '*.c' -o -name '*.mm' -o -name '*.cpp' \))
InsulationPrefs_CFLAGS = -fobjc-arc -ISources/InsulationPrefsC/include

InsulationPrefs_INSTALL_PATH = /Library/PreferenceBundles
ifeq ($(THEOS_PACKAGE_SCHEME),roothide)
InsulationPrefs_LDFLAGS += -lroothide
endif
InsulationPrefs_PRIVATE_FRAMEWORKS = Preferences

include $(THEOS_MAKE_PATH)/bundle.mk
