# ScriptsCollection

A small collection of macOS automation tools, utility scripts, and PopClip extensions.

## Project Tree

```text
├── AppleScripts/                               AppleScript utilities for Safari, Spotify, Chrome, and System Settings automation.
├── ShellScripts/                               Shell helpers for Finder defaults, media cleanup, photo printing, and Spotify workflows.
│   ├── clean-jellyfin-artefacts.sh             Safe Jellyfin artefact cleanup script with dry-run default.
│   └── spotify-keyboard-maestro-automator/     Supporting scripts, config, and macro files for Spotify playback automation.
├── SwiftScripts/                               Swift-based utilities and small local tools.
│   └── PlantLabels/                            Generates 3D-printable plant label variants from plant names and reference STL files.
│       ├── example/                            Reference STL files plus original design assets for the label shapes.
│       ├── output/                             Generated sample exports and test meshes.
│       ├── generate_plant_labels.swift         Main CLI script for single-label and batch exports.
│       └── README.md                           Usage notes, required assets, and export options for PlantLabels.
├── popclip/                                    PopClip extension packages.
│   └── whatsapp/                               PopClip extension for opening a WhatsApp chat from selected text.
│       ├── WhatsApp.popclipext/                Installable PopClip extension bundle.
│       └── README.md                           Setup notes for the WhatsApp PopClip extension.
└── README.md                                   Repository overview and usage summary.
```

## AppleScripts

- `AppleScripts/safari-urls-to-text-file.applescript` - Exports unique URLs from all open Safari tabs to a text file on the Desktop. Usage: Run from Script Editor or Shortcuts while Safari is open. Requires: Safari access.
- `AppleScripts/settings-hide-widgets-on-mac.applescript` - Opens System Settings and disables desktop widgets. Usage: Run from Script Editor or Shortcuts. Requires: System Events UI scripting permissions.
- `AppleScripts/settings-show-widgets-on-mac.applescript` - Opens System Settings and enables desktop widgets. Usage: Run from Script Editor or Shortcuts. Requires: System Events UI scripting permissions.
- `AppleScripts/spotify-decrease-volume.applescript` - Lowers Spotify volume by 5. Usage: Run from Script Editor or Shortcuts while Spotify is available. Requires: Spotify automation permission.
- `AppleScripts/spotify-increase-volume.applescript` - Raises Spotify volume by 5. Usage: Run from Script Editor or Shortcuts while Spotify is available. Requires: Spotify automation permission.
- `AppleScripts/spotify-next-track.applescript` - Skips to the next Spotify track. Usage: Run from Script Editor or Shortcuts while Spotify is playing. Requires: Spotify automation permission.
- `AppleScripts/spotify-previous-track.applescript` - Goes to the previous Spotify track. Usage: Run from Script Editor or Shortcuts while Spotify is playing. Requires: Spotify automation permission.
- `AppleScripts/spotify-select-random-playlist.applescript` - Picks a random playlist from a predefined list and opens it in Spotify or a browser. Usage: Run from Script Editor or Shortcuts. Requires: Spotify automation permission.
- `AppleScripts/text-file-urls-open-in-chrome.scpt` - Reads URLs from a text file and opens them in Google Chrome tabs. Usage: Run the compiled script from Script Editor or Finder. Requires: Google Chrome access.

## Shell Scripts

- `ShellScripts/clean-jellyfin-artefacts.sh` - Safely finds and removes known Jellyfin artefact folders (such as `.trickplay` and `EpisodeName.trickplay`) from a chosen media root. Usage: drag a folder into Terminal as the final argument. Defaults to a safe preview mode (`--dry-run`), and only deletes when `--apply` is provided. Requires: macOS Terminal with `bash`, `find`, and `du`.
  - Preview only (safe default): `./ShellScripts/clean-jellyfin-artefacts.sh "/Volumes/ExternalDisk/Media"`
  - Delete artefacts: `./ShellScripts/clean-jellyfin-artefacts.sh --apply "/Volumes/ExternalDisk/Media"`
  - Drag-and-drop compatibility: quoted escaped paths like `"/Volumes/My\ Disk/Show\ Name"` are accepted and normalized safely.
  - Safety: only allowlisted Jellyfin artefact folder names are targeted, and media files are never targeted directly.
- `ShellScripts/print-random-favorite.sh` - Prints a random Favorite photo from Apple Photos using a 13x18 cm preset. Usage: Run via terminal with `zsh`. Requires: Apple Photos access and a configured printer preset.
- `ShellScripts/set-finder-default-home.sh` - Sets Finder's default new-window folder to the configured home path. Usage: Run via terminal with `zsh`. Requires: macOS `defaults` and Finder restart.
- `ShellScripts/set-finder-default-work.sh` - Sets Finder's default new-window folder to the configured work path. Usage: Run via terminal with `zsh`. Requires: macOS `defaults` and Finder restart.
- `ShellScripts/spotify-keyboard-maestro-automator` - A Keyboard Maestro driven Spotify workflow with helper scripts for choosing a playback destination, starting a random playlist, and stopping playback. Usage: Configure the included Keyboard Maestro macro and shell scripts together. Requires: Keyboard Maestro, Spotify, and the files in this folder.

## Swift Scripts

- `SwiftScripts/PlantLabels` - A local macOS Swift project that generates three 3D-printable plant label variants from a plant name and exports them as STL, 3MF, OBJ, or all formats in one run. Usage: Run `generate_plant_labels.swift` with `swift` for a single plant name or a batch input file. Requires: macOS, the reference STL files in `SwiftScripts/PlantLabels/example/`, and `/Library/Fonts/Merriweather_BoldItalic.ttf`.

## PopClip Extensions

- `popclip/whatsapp/WhatsApp.popclipext` - Starts a new WhatsApp chat using the selected phone number. Usage: Install by double-clicking the extension bundle in Finder, then select a number in any app and trigger PopClip. Requires: PopClip and WhatsApp or WhatsApp Web.
