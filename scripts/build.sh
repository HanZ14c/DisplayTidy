#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
variant=""
if [[ "${1:-}" == "--sandbox" ]]; then
  variant="-Sandbox"
elif [[ $# -ne 0 ]]; then
  echo "Usage: $0 [--sandbox]" >&2
  exit 1
fi
staging=$(mktemp -d /private/tmp/DisplayTidy-build.XXXXXX)
trap 'rm -rf "$staging"' EXIT
app="$staging/DisplayTidy${variant}.app"
destination="$PWD/build/DisplayTidy${variant}.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" .build/module-cache
xcrun swiftc -parse-as-library -swift-version 6 -target arm64-apple-macosx13.0 -module-cache-path "$PWD/.build/module-cache" Sources/*.swift -o "$app/Contents/MacOS/DisplayTidy" -framework AppKit -framework SwiftUI -framework CoreGraphics -framework ColorSync -framework ServiceManagement
cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>DisplayTidy</string>
<key>CFBundleIdentifier</key><string>local.DisplayTidy${variant}</string>
<key>CFBundleName</key><string>DisplayTidy${variant}</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleDevelopmentRegion</key><string>en</string>
<key>CFBundleLocalizations</key><array><string>en</string><string>zh-Hans</string></array>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>LSUIElement</key><true/>
</dict></plist>
PLIST
cp -R Resources/. "$app/Contents/Resources/"
xattr -cr "$app"
if [[ -n "$variant" ]]; then
  codesign --force --sign - --entitlements scripts/Sandbox.entitlements "$app"
else
  codesign --force --sign - "$app"
fi
# Sign and verify outside the file-provider-managed workspace.
xattr -cr "$app"
codesign --verify --strict "$app"
mkdir -p build
ditto --norsrc "$app" "$destination"
printf '%s\n' "$destination"
