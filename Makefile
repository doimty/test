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
# General telemetry and the targeted CPMS ABI probe are opt-in diagnostics.
# CPMS package: make package FINALPACKAGE=1 PACKAGE_BUILDNAME=cpmsprobe1 INSULATION_CPMS_PROBE_ENABLED=1
INSULATION_PROBE_ENABLED ?= 0
INSULATION_CPMS_PROBE_ENABLED ?= 0
insulation_OBJC_FILES = $(shell find Sources/insulationObjC -type f \( -name '*.m' -o -name '*.c' -o -name '*.mm' -o -name '*.cpp' \) $(if $(filter 1,$(INSULATION_PROBE_ENABLED)),,! -name 'InsulationProbe.m') $(if $(filter 1,$(INSULATION_CPMS_PROBE_ENABLED)),,! -name 'InsulationCPMSProbe.m'))
insulation_C_FILES = $(shell find Sources/insulationC -type f \( -name '*.m' -o -name '*.c' -o -name '*.mm' -o -name '*.cpp' \) ! -name 'Tweak.m')
insulation_FILES = $(insulation_OBJC_FILES) $(insulation_C_FILES)

insulation_CFLAGS = -fobjc-arc -DINSULATION_PROBE_ENABLED=$(INSULATION_PROBE_ENABLED) -DINSULATION_CPMS_PROBE_ENABLED=$(INSULATION_CPMS_PROBE_ENABLED) -ISources/insulationC/include -ISources/insulationObjC
ifeq ($(THEOS_PACKAGE_SCHEME),roothide)
insulation_LDFLAGS += -lroothide
endif
insulation_FRAMEWORKS = SystemConfiguration
insulation_PRIVATE_FRAMEWORKS = IOKit

include $(THEOS_MAKE_PATH)/tweak.mk

TOOL_NAME = insulationctl
insulationctl_FILES = Sources/insulationctl/main.m \
Sources/insulationctl/InsulationCtlArgs.c
insulationctl_CFLAGS = -fobjc-arc -ISources/insulationctl
insulationctl_LDFLAGS = -Wl,-dead_strip_dylibs
insulationctl_FRAMEWORKS = Foundation
include $(THEOS_MAKE_PATH)/tool.mk

SUBPROJECTS += InsulationPrefs InsulationCC
include $(THEOS_MAKE_PATH)/aggregate.mk
