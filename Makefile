ARCHS = arm64 arm64e
TARGET := iphone:clang:latest:15.0
INSTALL_TARGET_PROCESSES = SpringBoard UserNotificationsUIServer

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = ProMotion120
ProMotion120_FILES = Tweak.xm
ProMotion120_CFLAGS = -fobjc-arc
ProMotion120_FRAMEWORKS = Foundation UIKit QuartzCore
ProMotion120_PRIVATE_FRAMEWORKS = SpringBoardFoundation
ProMotion120_LIBRARIES = substrate

include $(THEOS_MAKE_PATH)/tweak.mk
