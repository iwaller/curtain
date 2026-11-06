#!/bin/zsh
# Copies build/Curtain.app to /Applications and restarts it. Refuses while the curtain is closed,
# because quitting would uncover the screen.
set -euo pipefail
cd "${0:A:h:h}"
log=~/Library/Logs/Curtain/curtain.log
running=$(pgrep -x Curtain || true)
if [[ -n "$running" ]]; then
  if [[ "$running" == *$'\n'* ]]; then
    print -u2 "Multiple Curtain processes are running; stop the extra instances first."
    exit 1
  fi
  # A killed process can leave 'closed' as its final state. Only trust this PID's launch/session.
  last=$(awk -v curtain_pid="$running" '
    $2 == "launched" { current = ($3 == "pid=" curtain_pid); state = current ? "open" : "" }
    current && $2 == "state" { state = $5 }
    END { print state }
  ' "$log" 2>/dev/null || true)
  if [[ "$last" != "open" ]]; then
    print -u2 "Curtain is not open ($last); open it first."
    exit 1
  fi
  kill -TERM "$running"
  for attempt in {1..50}; do
    if ! kill -0 "$running" 2>/dev/null; then break; fi
    sleep 0.1
  done
  if kill -0 "$running" 2>/dev/null; then
    print -u2 "Curtain did not exit within 5 seconds; installation stopped."
    exit 1
  fi
fi
rm -rf /Applications/Curtain.app
ditto build/Curtain.app /Applications/Curtain.app
open /Applications/Curtain.app
print "Installed and started /Applications/Curtain.app"
