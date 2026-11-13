#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

APP_VERSION="${TEXTLENS_VERSION:-0.1.0}"
if [[ ! "$APP_VERSION" =~ ^[0-9]+(\.[0-9]+){2}$ ]]; then
	printf 'Error: TEXTLENS_VERSION must be a three-part numeric version (for example, 0.1.0); got: %s\n' "$APP_VERSION" >&2
	exit 1
fi

ICON_SOURCE="$ROOT_DIR/Resources/AppIcon.png"
if [[ ! -f "$ICON_SOURCE" ]]; then
	printf 'Error: required app icon is missing: %s\n' "$ICON_SOURCE" >&2
	exit 1
fi

if ! ICON_METADATA="$(/usr/bin/sips -g format -g pixelWidth -g pixelHeight "$ICON_SOURCE" 2>&1)"; then
	printf 'Error: app icon is not a readable PNG: %s\nDetails: %s\n' "$ICON_SOURCE" "$ICON_METADATA" >&2
	exit 1
fi

ICON_FORMAT="$(printf '%s\n' "$ICON_METADATA" | /usr/bin/awk '$1 == "format:" { print $2 }')"
ICON_WIDTH="$(printf '%s\n' "$ICON_METADATA" | /usr/bin/awk '$1 == "pixelWidth:" { print $2 }')"
ICON_HEIGHT="$(printf '%s\n' "$ICON_METADATA" | /usr/bin/awk '$1 == "pixelHeight:" { print $2 }')"
if [[ "$ICON_FORMAT" != "png" || "$ICON_WIDTH" != "1024" || "$ICON_HEIGHT" != "1024" ]]; then
	printf 'Error: app icon must be a 1024x1024 PNG; found format=%s size=%sx%s at %s\n' \
		"${ICON_FORMAT:-unknown}" "${ICON_WIDTH:-unknown}" "${ICON_HEIGHT:-unknown}" "$ICON_SOURCE" >&2
	exit 1
fi

swift build -c release --product TextLensApp
BIN_DIR="$(swift build -c release --show-bin-path)"

APP_DIR="$ROOT_DIR/dist/TextLens.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
ICONSET_DIR="$RESOURCES_DIR/TextLens.iconset"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$ICONSET_DIR"
cp "$BIN_DIR/TextLensApp" "$MACOS_DIR/TextLensApp"

# SwiftPM dependencies resolve Bundle.module from the app's Resources directory.
for resource_bundle in "$BIN_DIR"/*.bundle; do
	[[ -d "$resource_bundle" ]] || continue
	cp -R "$resource_bundle" "$RESOURCES_DIR/"
done

iconset_sizes=(
	'icon_16x16.png:16'
	'icon_16x16@2x.png:32'
	'icon_32x32.png:32'
	'icon_32x32@2x.png:64'
	'icon_128x128.png:128'
	'icon_128x128@2x.png:256'
	'icon_256x256.png:256'
	'icon_256x256@2x.png:512'
	'icon_512x512.png:512'
	'icon_512x512@2x.png:1024'
)
for entry in "${iconset_sizes[@]}"; do
	filename="${entry%%:*}"
	size="${entry##*:}"
	/usr/bin/sips -z "$size" "$size" "$ICON_SOURCE" --out "$ICONSET_DIR/$filename" >/dev/null
done
/usr/bin/iconutil -c icns "$ICONSET_DIR" -o "$RESOURCES_DIR/AppIcon.icns"
rm -rf "$ICONSET_DIR"

cat > "$CONTENTS_DIR/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleExecutable</key>
	<string>TextLensApp</string>
	<key>CFBundleIconFile</key>
	<string>AppIcon</string>
	<key>CFBundleIdentifier</key>
	<string>com.textlens.app</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>TextLens</string>
	<key>CFBundleShortVersionString</key>
	<string>${APP_VERSION}</string>
	<key>CFBundleVersion</key>
	<string>${APP_VERSION}</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>LSMinimumSystemVersion</key>
	<string>14.0</string>
	<key>LSUIElement</key>
	<true/>
	<key>NSScreenCaptureUsageDescription</key>
	<string>TextLens captures the region you select so it can recognize text locally.</string>
</dict>
</plist>
PLIST

printf 'Built app bundle: %s\n' "$APP_DIR"
