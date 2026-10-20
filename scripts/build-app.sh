#!/bin/zsh
set -euo pipefail

cd "${0:A:h}/.."
swift build -c release --product Tile

app_dir="${PWD}/dist/Tile.app"
mkdir -p "${app_dir}/Contents/MacOS"
cp .build/release/Tile "${app_dir}/Contents/MacOS/Tile"
cat > "${app_dir}/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleExecutable</key><string>Tile</string>
  <key>CFBundleIdentifier</key><string>dev.tile.app</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>Tile</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "${app_dir}"
print "Built ${app_dir}"
