#!/bin/zsh
set -euo pipefail

cd "${0:A:h}/.."
swift build -c release --product Tile

app_dir="${PWD}/dist/Tile.app"
if [[ -d "${app_dir}" ]]; then
  chmod -R u+w "${app_dir}"
fi
mkdir -p "${app_dir}/Contents/MacOS"
mkdir -p "${app_dir}/Contents/Resources/Licenses"
cp .build/release/Tile "${app_dir}/Contents/MacOS/Tile"
cp -R .build/release/Tile_Tile.bundle "${app_dir}/Contents/Resources/"
iconset="${PWD}/dist/Tile.iconset"
mkdir -p "${iconset}"
swift scripts/render-icon.swift Sources/Tile/Resources/TileLogo.png "${iconset}"
iconutil -c icns "${iconset}" -o "${app_dir}/Contents/Resources/Tile.icns"
cp LICENSE "${app_dir}/Contents/Resources/Licenses/Tile.txt"
cp .build/checkouts/SwiftTerm/LICENSE "${app_dir}/Contents/Resources/Licenses/SwiftTerm.txt"
cp .build/checkouts/swift-png/LICENSE "${app_dir}/Contents/Resources/Licenses/swift-png.txt"
cp .build/checkouts/h/LICENSE "${app_dir}/Contents/Resources/Licenses/h.txt"
cp .build/checkouts/swift-argument-parser/LICENSE.txt "${app_dir}/Contents/Resources/Licenses/swift-argument-parser.txt"
cat > "${app_dir}/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleExecutable</key><string>Tile</string>
  <key>CFBundleIdentifier</key><string>dev.tile.app</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>Tile</string>
  <key>CFBundleIconFile</key><string>Tile.icns</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "${app_dir}"
ditto -c -k --sequesterRsrc --keepParent "${app_dir}" "${PWD}/dist/Tile-macOS-arm64.zip"
print "Built ${app_dir}"
print "Archive ${PWD}/dist/Tile-macOS-arm64.zip"
