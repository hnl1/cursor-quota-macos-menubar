#!/bin/zsh
set -euo pipefail

project_dir=${0:A:h:h}
hook_src="$project_dir/hooks/nudge-refresh.sh"
hook_dir="$HOME/.cursor/hooks"
hook_dst="$hook_dir/nudge-cursor-quota.sh"
hooks_json="$HOME/.cursor/hooks.json"

mkdir -p "$hook_dir"
cp "$hook_src" "$hook_dst"
chmod 755 "$hook_dst"

python3 - "$hooks_json" <<'PY'
import json, sys
from pathlib import Path

path = Path(sys.argv[1])
entry = {"command": "./hooks/nudge-cursor-quota.sh", "timeout": 5}
data = {"version": 1, "hooks": {}}
if path.exists():
    try:
        loaded = json.loads(path.read_text())
        if isinstance(loaded, dict):
            data.update(loaded)
    except json.JSONDecodeError:
        pass
hooks = data.setdefault("hooks", {})
if not isinstance(hooks, dict):
    hooks = {}
    data["hooks"] = hooks

def ensure(event: str) -> None:
    items = hooks.get(event, [])
    if not isinstance(items, list):
        items = []
    commands = {
        item.get("command")
        for item in items
        if isinstance(item, dict)
    }
    if "./hooks/nudge-cursor-quota.sh" not in commands:
        items.append(entry)
    hooks[event] = items

ensure("stop")
ensure("sessionEnd")
data["version"] = 1
path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n")
PY

echo "已写入 Cursor 用户 hook: $hook_dst"
