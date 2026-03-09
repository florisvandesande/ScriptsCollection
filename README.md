# AppleScript-collection
A small collection of automation scripts for macOS.

## AppleScripts
- `AppleScripts/safari-urls-to-text-file.applescript` - Exports unique URLs from all open Safari tabs to a text file on the Desktop. Usage: Run from Script Editor/Shortcuts while Safari is open. Requires: Safari access.
- `AppleScripts/settings-hide-widgets-on-mac.applescript` - Opens System Settings and disables desktop widgets. Usage: Run from Script Editor/Shortcuts. Requires: System Events UI scripting permissions.
- `AppleScripts/settings-show-widgets-on-mac.applescript` - Opens System Settings and enables desktop widgets. Usage: Run from Script Editor/Shortcuts. Requires: System Events UI scripting permissions.
- `AppleScripts/spotify-decrease-volume.applescript` - Lowers Spotify volume by 5. Usage: Run from Script Editor/Shortcuts while Spotify is available. Requires: Spotify automation permission.
- `AppleScripts/spotify-increase-volume.applescript` - Raises Spotify volume by 5. Usage: Run from Script Editor/Shortcuts while Spotify is available. Requires: Spotify automation permission.
- `AppleScripts/spotify-next-track.applescript` - Skips to the next Spotify track. Usage: Run from Script Editor/Shortcuts while Spotify is playing. Requires: Spotify automation permission.
- `AppleScripts/spotify-previous-track.applescript` - Goes to the previous Spotify track. Usage: Run from Script Editor/Shortcuts while Spotify is playing. Requires: Spotify automation permission.
- `AppleScripts/spotify-select-random-playlist.applescript` - Picks a random playlist from a predefined list and opens it in Spotify/browser. Usage: Run from Script Editor/Shortcuts. Requires: Spotify automation permission.
- `AppleScripts/text-file-urls-open-in-chrome.scpt` - Reads URLs from a text file and opens them in Google Chrome tabs. Usage: Run compiled script from Script Editor/Finder. Requires: Google Chrome access.

## Shell Scripts
- `ShellScripts/set-finder-default-home.sh` - Sets Finder's default new-window folder to the configured home path. Usage: Run via terminal with `zsh`. Requires: macOS `defaults` and Finder restart.
- `ShellScripts/set-finder-default-work.sh` - Sets Finder's default new-window folder to the configured work path. Usage: Run via terminal with `zsh`. Requires: macOS `defaults` and Finder restart.
- `ShellScripts/spotify-keyboard-maestro-automator` - A set of scripts and files to play a random playlist on Spotify with a Keyboard Maestro macro to set playback destination. 
- `ShellScripts/print-random-favorite` - Print a random Favorite photo from Apple Photos on you printer with a preset at 13x18cm. 

## PopClip Extensions
- `popclip/whatsapp/WhatsApp.popclipext` - Starts a new WhatsApp chat using the selected phone number. Usage: Install by double-clicking in Finder, then select a number in any app and trigger PopClip. Requires: PopClip and WhatsApp (or WhatsApp Web in browser).
