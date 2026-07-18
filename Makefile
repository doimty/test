THEOS_PACKAGE_SCHEME = roothide
ARCHS = arm64e
TARGET := iphone:clang:latest:15.0

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = ProMotion120
ProMotion120_FILES = Tweak.xmi
ProMotion120_FRAMEWORKS = UIKit QuartzCore
ProMotion120_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/tweak.mk
