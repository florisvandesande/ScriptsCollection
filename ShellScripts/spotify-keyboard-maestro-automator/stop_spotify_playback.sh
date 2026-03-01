#!/usr/bin/env bash
set -euo pipefail

result="$(/usr/bin/osascript <<'APPLESCRIPT'
if application "Spotify" is running then
  tell application "Spotify"
    if player state is playing then
      pause
      return "paused"
    else
      return "already_not_playing"
    end if
  end tell
else
  return "spotify_not_running"
end if
APPLESCRIPT
)"

case "$result" in
  paused)
    echo "Spotify playback paused."
    ;;
  already_not_playing)
    echo "Spotify was already not playing."
    ;;
  spotify_not_running)
    echo "Spotify is not running."
    ;;
  *)
    echo "Unexpected result: $result" >&2
    exit 1
    ;;
esac
