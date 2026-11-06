#!/bin/zsh
# Image and cache lifecycle checks; no windows, display changes or authentication.
set -euo pipefail
cd "${0:A:h:h}"
mkdir -p build/module-cache
xcrun swiftc -module-cache-path build/module-cache -framework AppKit \
  Sources/App/BackdropArt.swift Sources/Shared/Log.swift Tests/BackdropArtTests.swift -o build/backdrop-art-tests
./build/backdrop-art-tests
