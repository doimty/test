ifndef THEOS
$(error THEOS is not set. Install Theos and export THEOS=/path/to/theos before building.)
endif

TARGET := iphone:clang:16.5:15.0

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = InsulationCC

InsulationCC_FILES = Sources/InsulationCCModule.m
InsulationCC_INSTALL_PATH = /Library/ControlCenter/Bundles
InsulationCC_RESOURCE_DIRS = Resources
InsulationCC_CFLAGS = -fobjc-arc -Iinclude -I../InsulationPrefs/Sources/InsulationPrefsC/include
ifeq ($(THEOS_PACKAGE_SCHEME),roothide)
InsulationCC_LDFLAGS += -lroothide
endif
InsulationCC_FRAMEWORKS = UIKit Foundation CoreFoundation QuartzCore
InsulationCC_PRIVATE_FRAMEWORKS = ControlCenterUIKit

include $(THEOS_MAKE_PATH)/bundle.mk
