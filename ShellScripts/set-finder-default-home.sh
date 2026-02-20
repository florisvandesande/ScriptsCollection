#!/bin/zsh
set -euo pipefail

TARGET_PATH='/Users/florisvandesande/Library/Mobile Documents/com~apple~CloudDocs/External Cortex'

if [[ ! -d "$TARGET_PATH" ]]; then
  echo "Folder does not exist: $TARGET_PATH" >&2
  exit 1
fi

# Finder expects a file:// URL in NewWindowTargetPath.
if command -v python3 >/dev/null 2>&1; then
  TARGET_URL="$(python3 -c 'import pathlib,sys; p = pathlib.Path(sys.argv[1]).resolve(); print(p.as_uri() + "/")' "$TARGET_PATH")"
else
  TARGET_URL="file://${TARGET_PATH// /%20}/"
fi

# Use custom path target so Finder uses NewWindowTargetPath.
defaults write com.apple.finder NewWindowTarget -string "PfLo"
defaults write com.apple.finder NewWindowTargetPath -string "$TARGET_URL"
killall Finder >/dev/null 2>&1 || true

echo "Finder default folder set to: $TARGET_PATH"
