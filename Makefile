ARCHS = arm64 arm64e
TARGET = iphone:latest:13.0

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = YLTool

YLTool_FILES = Tweak.xm
YLTool_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -fno-exceptions -Os
YLTool_LDFLAGS = -Wl,-dead_strip
YLTool_FRAMEWORKS = UIKit Foundation

include $(THEOS_MAKE_PATH)/tweak.mk
