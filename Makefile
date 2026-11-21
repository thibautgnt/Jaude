APP = Jaude.app

build:
	swift build -c release
	rm -rf $(APP) && mkdir -p $(APP)/Contents/MacOS
	cp .build/release/Jaude $(APP)/Contents/MacOS/
	cp Info.plist $(APP)/Contents/
	codesign --force --sign - $(APP)

install: build
	-pkill -x Jaude
	mkdir -p $(HOME)/Applications && rm -rf $(HOME)/Applications/$(APP) && cp -R $(APP) $(HOME)/Applications/
	open $(HOME)/Applications/$(APP)

check:
	mkdir -p .build
	swiftc Sources/Jaude/Usage.swift Tests/check/main.swift -o .build/check
	.build/check Tests/check/usage.json

.PHONY: build install check
