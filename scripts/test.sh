#!/bin/zsh
set -euo pipefail

project_dir=${0:A:h:h}
mkdir -p "$project_dir/build"

swiftc \
  -parse-as-library \
  -swift-version 6 \
  -strict-concurrency=complete \
  -target "$(uname -m)-apple-macosx26.0" \
  "$project_dir"/Tests/*.swift \
  "$project_dir"/Sources/Core/AppConfig.swift \
  "$project_dir"/Sources/Core/JSONNode.swift \
  "$project_dir"/Sources/Core/QuotaError.swift \
  "$project_dir"/Sources/Core/PanelLayout.swift \
  "$project_dir"/Sources/Core/MenuBarOptions.swift \
  "$project_dir"/Sources/Core/UsageModels.swift \
  "$project_dir"/Sources/Core/UsageParser.swift \
  -o "$project_dir/build/cursor-quota-tests"

"$project_dir/build/cursor-quota-tests"
