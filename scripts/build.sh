#!/bin/zsh
# Builds the menu bar app (build/Curtain.app) and the experiment CLI (build/curtain-poc).
# Signs with the first "Apple Development" identity when there is one, so macOS privacy
# permissions (Accessibility) survive rebuilds; falls back to ad-hoc. Override: CURTAIN_SIGN_IDENTITY.
set -euo pipefail
cd "${0:A:h:h}"
if [[ $(uname -m) != arm64 ]]; then
    print -u2 "Curtain supports arm64 only. Build on an Apple Silicon Mac from a native terminal."
    exit 1
fi
mkdir -p build/module-cache
# Supported: Apple Silicon, macOS 15 and later (keep in sync with Resources/Info.plist).
min_macos=15.0
swiftc_common=(xcrun swiftc -module-cache-path build/module-cache -target "arm64-apple-macos$min_macos")

identity=${CURTAIN_SIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null \
  | awk -F'"' '/Apple Development/ {print $2; exit}')}
identity=${identity:--}

# Pin publisher trust in the executable; a downloaded package cannot supply its own key.
update_public_key=$(./scripts/update-signing.sh validate-public Resources/UpdatePublicKey.txt)
print "enum UpdateTrust { static let publicKey = \"$update_public_key\" }" > build/UpdateTrust.swift

$swiftc_common -framework AppKit Sources/Shared/*.swift Sources/POC/main.swift -o build/curtain-poc

app=build/Curtain.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Helpers"
$swiftc_common -framework CoreGraphics Sources/Watchdog/*.swift -o "$app/Contents/Helpers/CurtainWatchdog"
codesign --force --timestamp=none --sign "$identity" "$app/Contents/Helpers/CurtainWatchdog" >/dev/null
$swiftc_common -framework AppKit -framework IOKit -framework ApplicationServices \
  Sources/Shared/*.swift Sources/App/*.swift build/UpdateTrust.swift -o "$app/Contents/MacOS/Curtain"
cp Resources/Info.plist "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CurtainUpdatePublicKey string $update_public_key" "$app/Contents/Info.plist"
# Include untracked source files in dirty detection (git diff alone misses them).
if git rev-parse --git-dir >/dev/null 2>&1; then
    commit=$(git rev-parse --short HEAD)
    if [[ -n $(git status --porcelain --untracked-files=normal) ]]; then
        commit="$commit-dirty"
    fi
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(git rev-list --count HEAD)" \
        -c "Add :CurtainCommit string $commit" "$app/Contents/Info.plist"
fi
# Layered Liquid Glass icon (Icon Composer format) -> Assets.car for macOS 26+, Curtain.icns for macOS 15.
mkdir -p "$app/Contents/Resources"
# Use macOS language selection, including per-app language preferences.
cp -R Resources/*.lproj "$app/Contents/Resources/"
xcrun actool "$PWD/Resources/Curtain.icon" --compile "$PWD/$app/Contents/Resources" --platform macosx \
  --minimum-deployment-target "$min_macos" --app-icon Curtain \
  --output-partial-info-plist "$PWD/build/icon-partial.plist" >/dev/null
codesign --force --timestamp=none --sign "$identity" "$app" >/dev/null
codesign --verify --deep --strict "$app"
rm -f build/Curtain.zip build/Curtain.zip.sig build/Curtain.dmg build/Curtain-arm64.dmg
# libarchive tar stores the exact signed tree; no Finder metadata/symlink payload is needed.
/usr/bin/tar --format zip -cf build/Curtain.zip -C build Curtain.app
print "Built build/curtain-poc, $app and build/Curtain.zip (signed: $identity)"
