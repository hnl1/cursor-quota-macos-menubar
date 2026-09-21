#!/bin/zsh
# Cursor hook: after an agent turn or session ends, ask Cursor Quota to refresh.
# stdin JSON is ignored; this hook must fail open and never block the agent.
cat >/dev/null || true

app="$HOME/Applications/Cursor Quota.app/Contents/MacOS/CursorQuota"

if pgrep -x CursorQuota >/dev/null 2>&1; then
  if [[ -x "$app" ]]; then
    "$app" --nudge >/dev/null 2>&1 || true
  else
    osascript -l JavaScript >/dev/null 2>&1 <<'EOF' || true
ObjC.import("Cocoa");
$.NSDistributedNotificationCenter.defaultCenter.postNotificationNameObjectUserInfoDeliverImmediately(
  "com.hnl1.cursorquota.nudge",
  null,
  {},
  true
);
EOF
  fi
else
  if [[ -d "$HOME/Applications/Cursor Quota.app" ]]; then
    open -g "$HOME/Applications/Cursor Quota.app" || true
  fi
fi

print -- '{}'
