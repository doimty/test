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
# 0.1.37+clean4: keep Package Version at 0.1.37; probe tax off; fail-closed removal lifecycle.
# Re-enable diagnostics with: make ... INSULATION_PROBE_ENABLED=1
INSULATION_PROBE_ENABLED ?= 0
insulation_OBJC_FILES = $(shell find Sources/insulationObjC -type f \( -name '*.m' -o -name '*.c' -o -name '*.mm' -o -name '*.cpp' \) $(if $(filter 1,$(INSULATION_PROBE_ENABLED)),,! -name 'InsulationProbe.m'))
insulation_C_FILES = $(shell find Sources/insulationC -type f \( -name '*.m' -o -name '*.c' -o -name '*.mm' -o -name '*.cpp' \) ! -name 'Tweak.m')
insulation_FILES = $(insulation_OBJC_FILES) $(insulation_C_FILES)

insulation_CFLAGS = -fobjc-arc -DINSULATION_PROBE_ENABLED=$(INSULATION_PROBE_ENABLED) -ISources/insulationC/include -ISources/insulationObjC
ifeq ($(THEOS_PACKAGE_SCHEME),roothide)
insulation_LDFLAGS += -lroothide
endif
insulation_FRAMEWORKS = SystemConfiguration
insulation_PRIVATE_FRAMEWORKS = IOKit

include $(THEOS_MAKE_PATH)/tweak.mk

TOOL_NAME = insulationctl
insulationctl_FILES = Sources/insulationctl/main.m \
Sources/insulationctl/InsulationCtlArgs.c \
Sources/insulationC/InsulationNativeState.m \
Sources/insulationC/InsulationRemovalProtocol.c \
Sources/insulationObjC/InsulationRemovalGuard.m
insulationctl_CFLAGS = -fobjc-arc -DINSULATION_REMOVAL_TOOL=1 -ISources/insulationctl -ISources/insulationC/include -ISources/insulationObjC
insulationctl_LDFLAGS = -Wl,-dead_strip_dylibs
insulationctl_FRAMEWORKS = Foundation SystemConfiguration
include $(THEOS_MAKE_PATH)/tool.mk

SUBPROJECTS += InsulationPrefs InsulationCC
include $(THEOS_MAKE_PATH)/aggregate.mk
