#!/bin/zsh
# Simulates display tables; never changes physical gamma or opens windows.
set -euo pipefail
cd "${0:A:h:h}"
mkdir -p build/module-cache
xcrun swiftc -module-cache-path build/module-cache -framework CoreGraphics \
  Sources/Shared/DisplayGamma.swift Sources/Shared/GammaLease.swift Sources/Shared/GammaBlackout.swift Sources/Shared/Log.swift \
  Tests/DisplayGammaTests.swift -o build/display-gamma-tests
./build/display-gamma-tests
# Hold the production ownership lock without changing gamma; the real CLI must refuse before CG calls.
xcrun swiftc -module-cache-path build/module-cache -framework AppKit \
  Sources/Shared/*.swift Sources/POC/main.swift -o build/curtain-poc-ownership-test
python3 - <<'PY'
import subprocess
holder = subprocess.Popen(['./build/display-gamma-tests', '--hold-default-lease'], stdout=subprocess.PIPE)
try:
    if holder.stdout.readline() == b'OWNED\n':
        result = subprocess.run(['./build/curtain-poc-ownership-test', '--gamma', '--duration', '2'],
                                capture_output=True, text=True, timeout=6)
        assert result.returncode == 1, (result.returncode, result.stdout, result.stderr)
        assert 'ownership-unavailable' in result.stdout and 'gamma-zero' not in result.stdout, result.stdout
        print('PASS real CLI refuses a held gamma lease with exit 1, without changing display tables')
    else:
        assert holder.wait(timeout=2) == 7
        print('SKIP real CLI probe: ownership unavailable; leave the running curtain untouched')
finally:
    if holder.poll() is None:
        holder.kill()
    holder.wait()
PY
