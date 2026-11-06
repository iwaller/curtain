#!/bin/zsh
# Copies build/Curtain.app to /Applications and restarts it. Refuses while the curtain is closed,
# because quitting would uncover the screen.
set -euo pipefail
cd "${0:A:h:h}"
log=~/Library/Logs/Curtain/curtain.log
if pgrep -x Curtain >/dev/null; then
  last=$(grep "state " "$log" 2>/dev/null | tail -1 || true)
  if [[ -n "$last" && "$last" != *"-> open"* ]]; then
    print -u2 "Curtain is not open ($last); open it first."
    exit 1
  fi
  pkill -TERM -x Curtain
  while pgrep -x Curtain >/dev/null; do sleep 0.2; done
fi
rm -rf /Applications/Curtain.app
ditto build/Curtain.app /Applications/Curtain.app
open /Applications/Curtain.app
print "Installed and started /Applications/Curtain.app"
