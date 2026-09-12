#!/bin/zsh
set -euo pipefail

project_dir=$0:A:h:h
build_dir="$project_dir/build"
app_dir="$build_dir/PISCOU, COPIOU.app"

cd "$project_dir"
swift build -c release

mkdir -p "$app_dir/Contents/MacOS"
mkdir -p "$app_dir/Contents/Resources"
swift scripts/build-icon.swift "$project_dir"
iconutil -c icns "Resources/AppIcon.iconset" -o "Resources/AppIcon.icns"
cp "Resources/AppIcon.icns" "$app_dir/Contents/Resources/AppIcon.icns"
cp ".build/release/TransferWatcher" "$app_dir/Contents/MacOS/PISCOU, COPIOU"
cp "Resources/Info.plist" "$app_dir/Contents/Info.plist"

codesign --force --sign - "$app_dir"
echo "$app_dir"
