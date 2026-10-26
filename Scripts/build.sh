#!/bin/bash
set -euo pipefail
AURALIS_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
AURALIS_APP="$AURALIS_ROOT/build/Auralis Native.app"
AURALIS_CACHE="${AURALIS_BUILD_CACHE:-$AURALIS_ROOT/build/module-cache}"
mkdir -p "$AURALIS_APP/Contents/MacOS" "$AURALIS_APP/Contents/Resources" "$AURALIS_CACHE"
/usr/bin/python3 "$AURALIS_ROOT/Scripts/generate-project.py"
xcrun swiftc -swift-version 5 -warnings-as-errors -O -target arm64-apple-macos14.0 -module-cache-path "$AURALIS_CACHE" \
 -framework AppKit -framework SwiftUI -framework WebKit -framework MediaPlayer -framework ImageIO \
 "$AURALIS_ROOT"/Auralis/{App,Core,Services,Views}/*.swift -o "$AURALIS_APP/Contents/MacOS/Auralis"
cp "$AURALIS_ROOT/Auralis/Resources/Info.plist" "$AURALIS_APP/Contents/Info.plist"
cp "$AURALIS_ROOT"/Auralis/Resources/*.js "$AURALIS_ROOT/Auralis/Resources/AppIcon.icns" "$AURALIS_APP/Contents/Resources/"
codesign --force --sign - --options runtime "$AURALIS_APP"
codesign --verify --deep --strict "$AURALIS_APP"
printf 'Built %s\n' "$AURALIS_APP"
