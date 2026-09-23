#!/bin/zsh
set -euo pipefail

project_dir=${0:A:h:h}
app_name="Cursor Quota"
install_dir=${CURSOR_QUOTA_INSTALL_DIR:-"$HOME/Applications"}
launch_after_install=1

if (( $# > 1 )) || [[ ${1:-} != "" && ${1:-} != "--no-launch" ]]; then
  print -u2 -- "用法: ./scripts/install.sh [--no-launch]"
  exit 64
fi

if [[ ${1:-} == "--no-launch" ]]; then
  launch_after_install=0
fi

"$project_dir/scripts/build.sh"

built_app="$project_dir/build/$app_name.app"
if [[ ! -d "$built_app" ]]; then
  print -u2 -- "构建没有生成 $built_app"
  exit 1
fi

mkdir -p "$install_dir"
destination_app="$install_dir/$app_name.app"

# 先关掉已经在跑的实例，避免覆盖正在使用的 bundle。
if pgrep -x CursorQuota >/dev/null 2>&1; then
  pkill -x CursorQuota || true
  sleep 0.4
fi

rm -rf "$destination_app"
ditto --noextattr --noqtn "$built_app" "$destination_app"
xattr -cr "$destination_app"
codesign --verify --deep --strict "$destination_app"

echo "已安装到 $destination_app"

"$project_dir/scripts/install-user-hook.sh"

if (( launch_after_install == 1 )); then
  open "$destination_app"
fi
