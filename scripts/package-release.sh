#!/bin/zsh
# Build the installer DMG and authenticate the update ZIP with the publisher's Ed25519 key.
set -euo pipefail
cd "${0:A:h:h}"
if [[ $# != 1 || ! -f "$1" ]]; then
    print -u2 "Usage: ./scripts/package-release.sh PATH_TO_PRIVATE_KEY"
    exit 1
fi
CURTAIN_SIGN_IDENTITY=${CURTAIN_SIGN_IDENTITY:--} ./scripts/build.sh
./scripts/update-signing.sh sign "$1" build/Curtain.zip
./scripts/package-dmg.sh
print "Release files: build/Curtain-arm64.dmg, build/Curtain.zip, build/Curtain.zip.sig"
