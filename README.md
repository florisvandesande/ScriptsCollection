# AppleScript-collection
a small collection of scripts

## scripts
- `safari-urls-to-text-file.applescript` — Save all Safari tab URLs to `~/Desktop/Safari-URLs.txt` (deduped, one per line). Usage: `osascript safari-urls-to-text-file.applescript`. Requires: Safari; write access to Desktop.
- `settings-hide-widgets-on-mac.applescript` — Open System Settings and turn off the “Toon Widgets” option. Usage: `osascript settings-hide-widgets-on-mac.applescript`. Requires: System Settings; System Events with Accessibility permission.
- `settings-show-widgets-on-mac.applescript` — Open System Settings and turn on the “Toon Widgets” option. Usage: `osascript settings-show-widgets-on-mac.applescript`. Requires: System Settings; System Events with Accessibility permission.
- `spotify-decrease-volume.applescript` — Lower Spotify volume by 5 (caps at 0–100). Usage: `osascript spotify-decrease-volume.applescript`. Requires: Spotify.
- `spotify-increase-volume.applescript` — Raise Spotify volume by 5 (caps at 0–100). Usage: `osascript spotify-increase-volume.applescript`. Requires: Spotify.
- `spotify-next-track.applescript` — Skip to the next Spotify track. Usage: `osascript spotify-next-track.applescript`. Requires: Spotify.
- `spotify-previous-track.applescript` — Return to the previous Spotify track. Usage: `osascript spotify-previous-track.applescript`. Requires: Spotify.
- `spotify-select-random-playlist.applescript` — Pick a random playlist from a predefined list, enable shuffle, and open it. Usage: `osascript spotify-select-random-playlist.applescript`. Requires: Spotify; default browser for playlist links.
- `text-file-urls-open-in-chrome.scpt` — Open each URL from a text file (defaults to `~/Desktop/Safari-URLs.txt`) in new Chrome tabs. Usage: `osascript text-file-urls-open-in-chrome.scpt`; prompts for a file if the default is missing. Requires: Google Chrome.
