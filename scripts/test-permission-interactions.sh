#!/bin/zsh
# Briefly shows test-owned native windows; never opens Settings or changes permissions/gamma.
set -euo pipefail
cd "${0:A:h:h}"
mkdir -p build/module-cache
xcrun swiftc -module-cache-path build/module-cache -framework AppKit \
  Sources/App/PermissionGuide.swift Tests/PermissionInteractionTests.swift -o build/permission-interaction-tests
./build/permission-interaction-tests
