#!/bin/bash
# ./build.sh        build CurrencyPop.app next to this script
# ./build.sh test   run the arithmetic and formatting checks
# ./build.sh run    build, then launch it
set -euo pipefail
cd "$(dirname "$0")"

ARCH=$(uname -m)
DEPLOY="$ARCH-apple-macos14.0"
APP="CurrencyPop.app"

if [ "${1:-}" = "test" ]; then
  mkdir -p .build
  swiftc -target "$DEPLOY" Math.swift tests/main.swift -o .build/selftest
  exec .build/selftest
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

swiftc -O -target "$DEPLOY" Math.swift CurrencyPop.swift \
  -o "$APP/Contents/MacOS/CurrencyPop"

cp CurrencyPop.icns "$APP/Contents/Resources/"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleName</key><string>CurrencyPop</string>
	<key>CFBundleDisplayName</key><string>CurrencyPop</string>
	<key>CFBundleIdentifier</key><string>dev.local.currencypop</string>
	<key>CFBundleExecutable</key><string>CurrencyPop</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>CFBundleIconFile</key><string>CurrencyPop</string>
	<key>CFBundleShortVersionString</key><string>1.0</string>
	<key>CFBundleVersion</key><string>1</string>
	<key>LSMinimumSystemVersion</key><string>14.0</string>
	<key>NSHighResolutionCapable</key><true/>
	<!-- No Dock icon, no app switcher entry: menu bar only. -->
	<key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP" >/dev/null 2>&1 || true
echo "built $APP"

if [ "${1:-}" = "run" ]; then
  pkill -x CurrencyPop 2>/dev/null || true
  open "$APP"
  echo "running — look for ⇄ in the menu bar"
fi
