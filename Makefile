export PACKAGE_VERSION := 1.2.1

ARCHS := arm64 arm64e
TARGET := iphone:clang:16.5:14.0

include $(THEOS)/makefiles/common.mk

TWEAK_NAME := DayNightSwitch
DayNightSwitch_FILES += Tweak.xm
DayNightSwitch_FILES += DayNightSwitch.m
DayNightSwitch_FILES += StripedSwitch.m
DayNightSwitch_FILES += DongRiYueSwitch.m
DayNightSwitch_FILES += PlaneSwitch.m
DayNightSwitch_FILES += TeethSwitch.m
DayNightSwitch_CFLAGS += -fobjc-arc

DayNightSwitch_CFLAGS += -Wno-nullability-completeness

include $(THEOS_MAKE_PATH)/tweak.mk

after-install::
	install.exec "killall -9 SpringBoard"

SUBPROJECTS += daynightswitch

include $(THEOS_MAKE_PATH)/aggregate.mk
