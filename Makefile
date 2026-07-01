ARCHS = arm64
TARGET = iphone:latest:14.0

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = YLTool

YLTool_FILES = Tweak.xm
YLTool_CFLAGS = -fobjc-arc -fno-exceptions -Wno-deprecated-declarations -Os
YLTool_LDFLAGS = -Wl,-dead_strip
YLTool_ENTITLEMENTS = entitlements.plist
YLTool_FRAMEWORKS = UIKit Foundation QuartzCore
YLTool_LIBRARIES = substrate

include $(THEOS_MAKE_PATH)/tweak.mk
