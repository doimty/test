ifndef THEOS
$(error THEOS is not set. Install Theos and export THEOS=/path/to/theos before building.)
endif

export THEOS_DEVICE_IP = localhost
export THEOS_DEVICE_PORT = 2222

INSTALL_TARGET_PROCESSES = thermalmonitord

ifeq ($(THEOS_PACKAGE_SCHEME), rootless)
TARGET = iphone:clang:latest:15.0
else ifeq ($(THEOS_PACKAGE_SCHEME),roothide)
TARGET = iphone:clang:latest:15.0
else
TARGET = iphone:clang:latest:14.0
endif

ARCHS = arm64 arm64e
DEBUG = 0

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = insulation
insulation_USE_MODULES = 0
insulation_FILES = $(shell find Sources/insulationObjC -type f \( -name '*.m' -o -name '*.c' -o -name '*.mm' -o -name '*.cpp' \)) \
$(shell find Sources/insulationC -type f \( -name '*.m' -o -name '*.c' -o -name '*.mm' -o -name '*.cpp' \))

insulation_CFLAGS = -fobjc-arc -ISources/insulationC/include -ISources/insulationObjC
ifeq ($(THEOS_PACKAGE_SCHEME),roothide)
insulation_LDFLAGS += -lroothide
endif
insulation_FRAMEWORKS = SystemConfiguration
insulation_PRIVATE_FRAMEWORKS = IOKit

include $(THEOS_MAKE_PATH)/tweak.mk
SUBPROJECTS += InsulationPrefs InsulationCC
include $(THEOS_MAKE_PATH)/aggregate.mk
