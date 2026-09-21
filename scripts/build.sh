#!/bin/zsh
set -euo pipefail

project_dir=${0:A:h:h}
app_name="Cursor Quota"
app_dir="$project_dir/build/$app_name.app"
target_arch=${TARGET_ARCH:-$(uname -m)}
signing_identity=${CODE_SIGN_IDENTITY:--}

if [[ "$target_arch" != "arm64" && "$target_arch" != "x86_64" ]]; then
  print -u2 -- "不支持的架构: $target_arch"
  exit 1
fi

temporary_root=${TMPDIR:-/private/tmp}
staging_root=$(mktemp -d "${temporary_root%/}/cursor-quota-build.XXXXXX")
staging_app="$staging_root/$app_name.app"
contents_dir="$staging_app/Contents"
binary_dir="$contents_dir/MacOS"

cleanup() {
  rm -rf "$staging_root"
}
trap cleanup EXIT

mkdir -p "$binary_dir" "$project_dir/build/ModuleCache"

source_files=("$project_dir"/Sources/Core/*.swift "$project_dir"/Sources/App/*.swift)

swiftc \
  -O \
  -whole-module-optimization \
  -parse-as-library \
  -swift-version 6 \
  -strict-concurrency=complete \
  -target "$target_arch-apple-macosx26.0" \
  -module-cache-path "$project_dir/build/ModuleCache" \
  -framework AppKit \
  -framework Foundation \
  -lsqlite3 \
  "${source_files[@]}" \
  -o "$binary_dir/CursorQuota"

plutil -lint "$project_dir/Resources/Info.plist" >/dev/null
cp "$project_dir/Resources/Info.plist" "$contents_dir/Info.plist"

xattr -cr "$staging_app"
if [[ "$signing_identity" == "-" ]]; then
  codesign --force --sign - "$staging_app"
else
  codesign --force --sign "$signing_identity" --options runtime --timestamp "$staging_app"
fi
codesign --verify --deep --strict "$staging_app"

rm -rf "$app_dir"
ditto --noextattr --noqtn "$staging_app" "$app_dir"
xattr -cr "$app_dir"
codesign --verify --deep --strict "$app_dir"

echo "$app_dir"
