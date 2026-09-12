#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
swift build -c release --arch x86_64
swift scripts/build-icon.swift "$PWD"
iconutil -c icns Resources/AppIcon.iconset -o Resources/AppIcon.icns
app="build/intel/PISCOU, COPIOU.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp .build/x86_64-apple-macosx/release/TransferWatcher "$app/Contents/MacOS/PISCOU, COPIOU"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$app"
codesign --verify --strict "$app"
ditto -c -k --sequesterRsrc --keepParent "$app" build/Piscou-Copiou-Intel-macOS13.zip
