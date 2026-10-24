ARCHS = armv7
TARGET = iphone:clang:6.1:6.0

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = Pulse
Pulse_FILES = $(wildcard *.m)
Pulse_FRAMEWORKS = UIKit Foundation CoreGraphics QuartzCore CFNetwork Security AddressBook AddressBookUI
Pulse_CFLAGS = -fobjc-arc
Pulse_CODESIGN_FLAGS = -Sentitlements.plist

include $(THEOS_MAKE_PATH)/application.mk
