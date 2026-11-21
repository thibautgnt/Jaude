APP = Jaude.app
VERSION = $(shell plutil -extract CFBundleShortVersionString raw Info.plist)

build:
	swift build -c release
	rm -rf $(APP) && mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	cp .build/release/Jaude $(APP)/Contents/MacOS/
	cp Info.plist $(APP)/Contents/
	cp Icon/AppIcon.icns $(APP)/Contents/Resources/
	codesign --force --sign - $(APP)

install: build
	-pkill -x Jaude
	mkdir -p $(HOME)/Applications && rm -rf $(HOME)/Applications/$(APP) && cp -R $(APP) $(HOME)/Applications/
	open $(HOME)/Applications/$(APP)

check:
	mkdir -p .build
	swiftc Sources/Jaude/Usage.swift Tests/check/main.swift -o .build/check
	.build/check Tests/check/usage.json

# Regenerates Icon/AppIcon.icns and docs/icon.png from Icon/render.swift.
icon:
	rm -rf .build/AppIcon.iconset && mkdir -p .build/AppIcon.iconset docs
	swift Icon/render.swift .build/icon-1024.png
	for s in 16 32 128 256 512; do \
		sips -z $$s $$s .build/icon-1024.png --out .build/AppIcon.iconset/icon_$${s}x$${s}.png >/dev/null; \
		sips -z $$((s * 2)) $$((s * 2)) .build/icon-1024.png --out .build/AppIcon.iconset/icon_$${s}x$${s}@2x.png >/dev/null; \
	done
	iconutil -c icns .build/AppIcon.iconset -o Icon/AppIcon.icns
	sips -z 256 256 .build/icon-1024.png --out docs/icon.png >/dev/null

# Builds Jaude.zip and Jaude-<version>.dmg in dist/ and publishes them as GitHub release v<version>.
release: check build
	rm -rf dist && mkdir -p dist/dmg
	ditto -c -k --keepParent $(APP) dist/Jaude.zip
	cp -R $(APP) dist/dmg/
	hdiutil create -volname Jaude -srcfolder dist/dmg -format UDZO -ov dist/Jaude-$(VERSION).dmg
	rm -rf dist/dmg
	gh release create v$(VERSION) dist/Jaude.zip dist/Jaude-$(VERSION).dmg --title "Jaude $(VERSION)" --generate-notes

.PHONY: build install check icon release
