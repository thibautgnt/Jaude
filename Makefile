APP = Jaude.app
VERSION = $(shell plutil -extract CFBundleShortVersionString raw Info.plist)
SIGN = -
DEVELOPER_ID = Developer ID Application: Thibaut Genet (33MB9HPP65)
# Stored once with: xcrun notarytool store-credentials notary
NOTARY_PROFILE = notary

build:
	swift build -c release
	rm -rf $(APP) && mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	cp .build/release/Jaude $(APP)/Contents/MacOS/
	cp Info.plist $(APP)/Contents/
	cp Icon/AppIcon.icns $(APP)/Contents/Resources/
	codesign --force --options runtime --timestamp$(if $(filter -,$(SIGN)),=none) --sign "$(SIGN)" $(APP)

install: build
	-pkill -x Jaude
	mkdir -p $(HOME)/Applications && rm -rf $(HOME)/Applications/$(APP) && cp -R $(APP) $(HOME)/Applications/
	open $(HOME)/Applications/$(APP)

check:
	mkdir -p .build
	swiftc Sources/Jaude/Usage.swift Sources/Jaude/LocalUsage.swift Tests/check/main.swift -o .build/check
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

release: SIGN = $(DEVELOPER_ID)

# Builds a notarized Jaude.zip and Jaude-<version>.dmg in dist/; publish publishes them as GitHub release v<version>.
release: check build
	rm -rf dist && mkdir -p dist/dmg
	cp -R $(APP) dist/dmg/
	ln -s /Applications dist/dmg/Applications
	hdiutil create -volname Jaude -srcfolder dist/dmg -format UDZO -ov dist/Jaude-$(VERSION).dmg
	rm -rf dist/dmg
	codesign --timestamp --sign "$(SIGN)" dist/Jaude-$(VERSION).dmg
	xcrun notarytool submit dist/Jaude-$(VERSION).dmg --keychain-profile $(NOTARY_PROFILE) --wait
	xcrun stapler staple dist/Jaude-$(VERSION).dmg
	xcrun stapler staple $(APP)
	ditto -c -k --keepParent $(APP) dist/Jaude.zip
	spctl --assess --type execute -v $(APP)

publish: release
	gh release create v$(VERSION) dist/Jaude.zip dist/Jaude-$(VERSION).dmg --title "Jaude $(VERSION)" --generate-notes

.PHONY: build install check icon release publish
