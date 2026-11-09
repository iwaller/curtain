#!/bin/zsh
# Image, transport and cache lifecycle checks; no display changes or authentication.
set -euo pipefail
cd "${0:A:h:h}"
mkdir -p build/module-cache
app=build/BackdropTests.app
mkdir -p "$app/Contents/MacOS" "$app/Contents/Helpers"
flags=(-Osize -whole-module-optimization -module-cache-path build/module-cache)
if [[ ${CURTAIN_TEST_ASAN:-0} == 1 ]]; then flags+=(-sanitize=address); fi
xcrun swiftc $flags -framework CoreGraphics -framework Accelerate \
  Sources/Backdrop/*.swift Sources/Rendering/*.swift -o "$app/Contents/Helpers/CurtainRenderer"
codesign --force --sign - "$app/Contents/Helpers/CurtainRenderer"
xcrun swiftc $flags -framework CoreGraphics Sources/Backdrop/*.swift Tests/FakeBackdropRenderer.swift -o build/fake-backdrop-renderer
codesign --force --sign - build/fake-backdrop-renderer
xcrun swiftc $flags -framework AppKit -framework Accelerate \
  Sources/App/BackdropArt.swift Sources/App/BackdropRenderJob.swift Sources/Backdrop/*.swift \
  Sources/Rendering/BackdropRenderer.swift Sources/Shared/Log.swift \
  Tests/BackdropArtTests.swift Tests/BackdropRendererTests.swift Tests/BackdropRenderJobTests.swift \
  -o "$app/Contents/MacOS/BackdropTests"
"./$app/Contents/MacOS/BackdropTests"
