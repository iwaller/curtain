#!/bin/zsh
# Offscreen production AppKit previews, without starting the real controller or changing TCC.
set -euo pipefail
cd "${0:A:h:h}"
app=build/PermissionPreview.app
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" build/module-cache artifacts/permission-redesign
xcrun swiftc -module-cache-path build/module-cache -framework AppKit \
    Sources/App/PermissionGuide.swift Tests/PermissionPreview.swift -o "$app/Contents/MacOS/PermissionPreview"
cp build/Curtain.app/Contents/Resources/Curtain.icns "$app/Contents/Resources/"
cp -R Resources/*.lproj "$app/Contents/Resources/"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>local.zjf.curtain.permission-preview</string>
<key>CFBundleName</key><string>Curtain</string>
<key>CFBundleExecutable</key><string>PermissionPreview</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleDevelopmentRegion</key><string>en</string>
<key>CFBundleLocalizations</key><array><string>en</string><string>zh-Hans</string></array>
<key>CFBundleIconFile</key><string>Curtain</string>
<key>LSUIElement</key><true/>
</dict></plist>
PLIST
for language in en zh-Hans; do
    "$app/Contents/MacOS/PermissionPreview" "$PWD/artifacts/permission-redesign/$language" \
        -AppleLanguages "($language)"
done
