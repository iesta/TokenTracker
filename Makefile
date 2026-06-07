APP = TokenTracker
SWIFT_SRCS = src/main.swift
swift_flags = -framework AppKit -framework SwiftUI -parse-as-library -target arm64-apple-macosx14.0

build:
	rm -rf $(APP).app
	mkdir -p $(APP).app/Contents/MacOS $(APP).app/Contents/Resources
	swiftc $(SWIFT_SRCS) $(swift_flags) -o $(APP).app/Contents/MacOS/$(APP)
	cp src/Info.plist $(APP).app/Contents/Info.plist
	codesign --force --deep --sign - $(APP).app

run: build
	open $(APP).app

clean:
	rm -rf $(APP).app
