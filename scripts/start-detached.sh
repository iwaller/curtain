#!/bin/zsh
# Start curtain-poc in its own session so it survives the launching shell.
# Usage: scripts/start-detached.sh <log-file> [curtain-poc args...]
set -euo pipefail
cd "${0:A:h:h}"
log_file="$1"; shift
exec python3 -I -c '
import subprocess, sys
log = open(sys.argv[1], "w")
p = subprocess.Popen(["./build/curtain-poc", *sys.argv[2:]], stdout=log, stderr=log,
                     stdin=subprocess.DEVNULL, start_new_session=True)
print(p.pid)
' "$log_file" "$@"
