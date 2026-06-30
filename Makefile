ARCHS = arm64 arm64e
TARGET = iphone:latest:13.0

INSTALL_TARGET_PROCESSES = YallaLite

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = YLTool

YLTool_FILES = Tweak.xm
YLTool_CFLAGS = -fobjc-arc -Wno-deprecated-declarations
YLTool_LDFLAGS =
YLTool_FRAMEWORKS = UIKit Foundation
YLTool_PRIVATE_FRAMEWORKS =

include $(THEOS_MAKE_PATH)/tweak.mk
