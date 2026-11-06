#!/bin/zsh
# Local release utility. Never reads a private key during a normal application build.
set -euo pipefail
cd "${0:A:h:h}"
mkdir -p build/module-cache
tool=build/update-signing
if [[ ! -x "$tool" || scripts/UpdateSigning.swift -nt "$tool" ]]; then
    xcrun swiftc -module-cache-path build/module-cache scripts/UpdateSigning.swift -o "$tool"
fi
exec "$tool" "$@"
