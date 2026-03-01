#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${1:-$ROOT_DIR/config.txt}"

if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "Config file not found: $CONFIG_FILE" >&2
  exit 1
fi

# shellcheck source=/dev/null
source "$CONFIG_FILE"

PLAYLIST_FILE="${PLAYLIST_FILE:-$ROOT_DIR/playlists.txt}"
if [[ "$PLAYLIST_FILE" != /* ]]; then
  PLAYLIST_FILE="$ROOT_DIR/$PLAYLIST_FILE"
fi

if [[ ! -f "$PLAYLIST_FILE" ]]; then
  if [[ -f "$ROOT_DIR/playlist.txt" ]]; then
    PLAYLIST_FILE="$ROOT_DIR/playlist.txt"
  else
    echo "Playlist file not found: $PLAYLIST_FILE" >&2
    exit 1
  fi
fi

LOG_FILE="${LOG_FILE:-$ROOT_DIR/logs/runner.log}"
if [[ "$LOG_FILE" != /* ]]; then
  LOG_FILE="$ROOT_DIR/$LOG_FILE"
fi
mkdir -p "$(dirname "$LOG_FILE")"

LOCK_FILE="${LOCK_FILE:-$ROOT_DIR/tmp/run.lock}"
if [[ "$LOCK_FILE" != /* ]]; then
  LOCK_FILE="$ROOT_DIR/$LOCK_FILE"
fi
mkdir -p "$(dirname "$LOCK_FILE")"

if ! mkdir "$LOCK_FILE" 2>/dev/null; then
  echo "Another run is still active, skipping." >&2
  exit 1
fi

cleanup_lock() {
  rmdir "$LOCK_FILE" >/dev/null 2>&1 || true
}
trap cleanup_lock EXIT

log() {
  local level="$1"
  shift
  local message="$*"
  printf '%s [%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$level" "$message" | tee -a "$LOG_FILE"
}

notify() {
  local title="$1"
  local message="$2"
  if [[ "${ENABLE_NOTIFICATIONS:-true}" == "true" ]]; then
    /usr/bin/osascript - "$title" "$message" >/dev/null 2>&1 <<'APPLESCRIPT' || true
on run argv
  set noteTitle to item 1 of argv
  set noteMessage to item 2 of argv
  display notification noteMessage with title noteTitle
end run
APPLESCRIPT
  fi
}

trim() {
  local x="$1"
  x="${x#"${x%%[![:space:]]*}"}"
  x="${x%"${x##*[![:space:]]}"}"
  printf '%s' "$x"
}

normalize_bool() {
  local raw
  raw="$(trim "${1:-}")"
  raw="$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]')"
  case "$raw" in
    1|true|yes|on) printf 'true' ;;
    0|false|no|off) printf 'false' ;;
    *) printf 'false' ;;
  esac
}

playlist_to_uri() {
  local input="$1"
  if [[ "$input" =~ ^spotify:playlist:[A-Za-z0-9]+$ ]]; then
    printf '%s' "$input"
    return 0
  fi

  if [[ "$input" =~ playlist/([A-Za-z0-9]+) ]]; then
    printf 'spotify:playlist:%s' "${BASH_REMATCH[1]}"
    return 0
  fi

  return 1
}

spotify_player_state() {
  /usr/bin/osascript -e 'tell application "Spotify" to player state as string' 2>/dev/null || true
}

play_playlist_locally() {
  local playlist_uri="$1"
  local shuffle_state="$2"
  local startup_wait="${SPOTIFY_STARTUP_WAIT_SECONDS:-2}"
  local state=""
  local attempt

  /usr/bin/open -a Spotify >/dev/null 2>&1 || true
  sleep "$startup_wait"

  for attempt in 1 2 3; do
    if /usr/bin/osascript - "$playlist_uri" "$shuffle_state" >/dev/null 2>&1 <<'APPLESCRIPT'
on run argv
  set playlistUri to item 1 of argv
  set shuffleState to item 2 of argv

  tell application "Spotify" to activate
  delay 1

  tell application "Spotify"
    try
      if shuffleState is "true" then
        set shuffling to true
      else
        set shuffling to false
      end if
    end try
    try
      -- Start playback in the selected playlist context instead of resuming old context.
      play track playlistUri
    on error
      -- Fallback path: navigate to the playlist, then retry direct context playback.
      open location playlistUri
      delay 1
      try
        play track playlistUri
      on error
        -- Last resort for older/broken clients: resume whatever Spotify can play.
        play
      end try
    end try
  end tell
end run
APPLESCRIPT
    then
      state="$(spotify_player_state)"
      if [[ "$state" == "playing" ]]; then
        return 0
      fi
    fi

    sleep 1
  done

  return 1
}

log "INFO" "Using config: $CONFIG_FILE"
log "INFO" "Using playlists: $PLAYLIST_FILE"

PLAYLIST_LINES=()
while IFS= read -r raw_line || [[ -n "$raw_line" ]]; do
  if [[ "$raw_line" =~ ^[[:space:]]*# ]] || [[ "$raw_line" =~ ^[[:space:]]*$ ]]; then
    continue
  fi
  PLAYLIST_LINES+=("$raw_line")
done < "$PLAYLIST_FILE"

if [[ ${#PLAYLIST_LINES[@]} -eq 0 ]]; then
  log "ERROR" "No playable lines in $PLAYLIST_FILE"
  notify "Spotify automation failed" "No playlists found"
  exit 1
fi

idx=$((RANDOM % ${#PLAYLIST_LINES[@]}))
line="${PLAYLIST_LINES[$idx]}"
playlist_name="${line%%:*}"
playlist_ref="${line#*:}"
playlist_name="$(trim "$playlist_name")"
playlist_ref="$(trim "$playlist_ref")"

if [[ -z "$playlist_name" || -z "$playlist_ref" || "$playlist_name" == "$playlist_ref" ]]; then
  log "ERROR" "Invalid playlist line: $line"
  notify "Spotify automation failed" "Invalid playlist line in playlists file"
  exit 1
fi

if ! playlist_uri="$(playlist_to_uri "$playlist_ref")"; then
  log "ERROR" "Cannot parse playlist reference: $playlist_ref"
  notify "Spotify automation failed" "Playlist URL/URI is invalid"
  exit 1
fi

shuffle_state="$(normalize_bool "${SPOTIFY_SHUFFLE:-true}")"
log "INFO" "Random playlist selected: $playlist_name ($playlist_uri)"

if ! play_playlist_locally "$playlist_uri" "$shuffle_state"; then
  log "ERROR" "Failed to start Spotify playback locally."
  notify "Spotify automation failed" "Could not start local Spotify playback"
  exit 1
fi

log "INFO" "Now playing '$playlist_name' in Spotify app"
notify "Spotify started" "$playlist_name"
