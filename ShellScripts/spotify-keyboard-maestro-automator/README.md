# Spotify Random Playlist Launcher (macOS)

Simple macOS scripts to:

- start a random Spotify playlist
- stop Spotify playback

This project is designed for local use with the Spotify desktop app and works well with Keyboard Maestro.

## Requirements

- macOS
- Spotify desktop app installed
- AppleScript permission to control Spotify (macOS may ask on first run)

## Files

- `play_random_playlist.sh`  
  Picks a random playlist from `playlists.txt` and starts playback in Spotify.
- `stop_spotify_playback.sh`  
  Pauses Spotify if it is currently playing.
- `playlists.txt`  
  List of playlists to choose from.
- `config.txt`  
  Settings for playlist file path, shuffle, startup wait, logging, and lock file.
- `Spotify_example_macros.kmmacros`  
  Example Keyboard Maestro macros for setting the playback destination to an AirPlay device and running the scripts.

## Playlist Format

Use one playlist per line in `playlists.txt`:

```text
Playlist Name: https://open.spotify.com/playlist/...
```

Also supported:

```text
Playlist Name: spotify:playlist:PLAYLIST_ID
```

Notes:

- Empty lines are ignored.
- Lines starting with `#` are ignored.

## Configuration

Default `config.txt`:

```bash
# Playlist launcher settings
PLAYLIST_FILE="./playlists.txt"

# Spotify playback settings
SPOTIFY_SHUFFLE="true"
SPOTIFY_STARTUP_WAIT_SECONDS="2"

# Files/paths (relative paths are resolved from bundle root)
LOG_FILE="./logs/runner.log"
LOCK_FILE="./tmp/run.lock"

# Logging/notifications
ENABLE_NOTIFICATIONS="true"
```

## Usage

From this folder:

```bash
./play_random_playlist.sh ./config.txt
./stop_spotify_playback.sh
```

Or with absolute paths:

```bash
/Users/USERNAME/spotify-keyboard-maestro-automator/play_random_playlist.sh /Users/USERNAME/spotify-keyboard-maestro-automator/config.txt
/Users/USERNAME/spotify-keyboard-maestro-automator/stop_spotify_playback.sh
```

## Keyboard Maestro

Use `Execute Shell Script` with:

- `with input from`: `nothing`
- `execute`: `text script`

Play random playlist:

```bash
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
cd /Users/USERNAME/spotify-keyboard-maestro-automator
./play_random_playlist.sh ./config.txt
```

Stop playback:

```bash
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
cd /Users/hethoogland/Repositories/Spotify
./stop_spotify_playback.sh
```

Optional debug logging:

```bash
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
cd /Users/hethoogland/Repositories/Spotify
./play_random_playlist.sh ./config.txt 2>&1 | tee -a ./logs/km-run.log
```

## Troubleshooting

- `Config file not found`: pass the correct `config.txt` path as script argument.
- `Playlist file not found`: check `PLAYLIST_FILE` in `config.txt`.
- Spotify does not start: open Spotify manually once and confirm you are signed in.
- Script runs but nothing plays: check `logs/runner.log`.
- Keyboard Maestro issue only: run the same command in Terminal first, then compare with `logs/km-run.log`.
