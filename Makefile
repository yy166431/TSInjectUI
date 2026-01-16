TARGET := iphone:clang:latest:14.0
ARCHS := arm64
INSTALL_TARGET_PROCESSES := WAppGames-mobile

include $(THEOS)/makefiles/common.mk

TWEAK_NAME := TSInjectUI
TSInjectUI_FILES := Tweak.xm
TSInjectUI_CFLAGS := -fobjc-arc
TSInjectUI_FRAMEWORKS := UIKit AudioToolbox

include $(THEOS_MAKE_PATH)/tweak.mk
