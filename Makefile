THEOS_PACKAGE_SCHEME ?= roothide
TARGET := iphone:clang:latest:15.0

include $(THEOS)/makefiles/common.mk

export ARCHS = arm64e
PM_FOREGROUND_PROBE_ENABLED ?= 1

TWEAK_NAME = ProMotion120
ProMotion120_FILES = Tweak.xmi
ProMotion120_FRAMEWORKS = UIKit QuartzCore
ProMotion120_CFLAGS = -fobjc-arc -DPM_FOREGROUND_PROBE_ENABLED=$(PM_FOREGROUND_PROBE_ENABLED)

include $(THEOS_MAKE_PATH)/tweak.mk
