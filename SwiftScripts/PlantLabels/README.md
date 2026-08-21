# Plantenlabels

This is local macOS Swift script that exports three plant-label variants as STL, 3MF, OBJ, or all three in one run.

## Current structure

```text
Plantenlabels/
├── example/
├── generate_plant_labels.swift
├── output/
└── README.md
```

## Reference files the script needs

The script reads these three STL files to recover the label outlines and text placement area:

- `example/plantlabel_rounded_corners.stl`
- `example/plantlabel_with_stick.stl`
- `example/plantlabel_inverted_rounded_corners.stl`

If you also keep these files in `example/`, they are useful as design reference, but the script does not read them directly:

- `plantlabels.ai`
- `plantlabels_without_text.dwg`

The script first looks in `example/`, then falls back to a few older compatibility locations.

## Before you run it

1. Make sure you are on macOS.
2. This script works on macOS 13 and newer.
3. Make sure the font file exists at `/Library/Fonts/Merriweather_BoldItalic.ttf`.
4. Make sure the three required reference STL files are present in `example/`.
5. Open Terminal in this folder.

If Swift reports a module-cache error that mentions `.cache/clang/ModuleCache`, use one of these fixes:

```bash
mkdir -p ~/.cache/clang/ModuleCache
```

Or run the script with an explicit writable cache path:

```bash
swift -module-cache-path /tmp/swift-module-cache generate_plant_labels.swift --name "Agastache rugosa 'Black Adder'"
```

## What the script exports

For each plant name, the script exports three label variants:

- rounded corners
- with stick
- inverted rounded corners

You can export them as:

- STL
- 3MF
- OBJ
- all three in one run

The script also creates a safe file-name slug from the plant name.

Example input:

```text
Agastache rugosa 'Black Adder'
```

Example output names:

```text
agastache-rugosa-black-adder-rounded-corners.stl
agastache-rugosa-black-adder-rounded-corners.3mf
agastache-rugosa-black-adder-rounded-corners.obj
```

## Single plant export

Default STL export:

```bash
swift generate_plant_labels.swift --name "Agastache rugosa 'Black Adder'"
```

3MF export:

```bash
swift generate_plant_labels.swift \
  --name "Agastache rugosa 'Black Adder'" \
  --format 3mf
```

OBJ export:

```bash
swift generate_plant_labels.swift \
  --name "Agastache rugosa 'Black Adder'" \
  --format obj
```

3MF with black letters:

```bash
swift generate_plant_labels.swift \
  --name "Agastache rugosa 'Black Adder'" \
  --format 3mf \
  --color-letters
```

3MF with black letters and border:

```bash
swift generate_plant_labels.swift \
  --name "Agastache rugosa 'Black Adder'" \
  --format 3mf \
  --color-letters \
  --color-border
```

OBJ with black letters and border:

```bash
swift generate_plant_labels.swift \
  --name "Agastache rugosa 'Black Adder'" \
  --format obj \
  --color-letters \
  --color-border
```

STL, 3MF, and OBJ in one run:

```bash
swift generate_plant_labels.swift \
  --name "Agastache rugosa 'Black Adder'" \
  --format all
```

## Batch export from a text file

Create a UTF-8 text file with one plant name per line.

Blank lines are ignored.

Lines that start with `#` are treated as comments and are ignored too.

Example:

```text
# Spring batch
Agastache rugosa 'Black Adder'

Hylotelephium spectabile 'Autumn Joy'
Héuchera 'Palace Purple'
```

Batch STL export:

```bash
swift generate_plant_labels.swift --input-file plant-names.txt
```

Batch 3MF export:

```bash
swift generate_plant_labels.swift \
  --input-file plant-names.txt \
  --format 3mf
```

Batch OBJ export:

```bash
swift generate_plant_labels.swift \
  --input-file plant-names.txt \
  --format obj
```

Batch full export:

```bash
swift generate_plant_labels.swift \
  --input-file plant-names.txt \
  --format all
```

Batch full export with black letters and border:

```bash
swift generate_plant_labels.swift \
  --input-file plant-names.txt \
  --format all \
  --color-letters \
  --color-border
```

## Where exported files go

By default, the script writes files to:

```text
/Users/<your-name>/Desktop/plantlabels/
```

The script creates that folder automatically if it does not exist yet.

If you want a different folder, use `--output-dir`:

```bash
swift generate_plant_labels.swift \
  --name "Agastache rugosa 'Black Adder'" \
  --format all \
  --output-dir /tmp/plantlabel-test
```

## CLI options

Supported format values:

- `stl`
- `3mf`
- `obj`
- `all`

If you do not set `--format`, the script exports STL only.

The old `--format both` value is no longer supported.

If you used that before, switch to:

```text
--format all
```

Input rules:

- use `--name` for one plant
- use `--input-file` for a batch
- do not use both together

Color-cap flags:

- `--color-letters`
- `--color-border`

These flags only work when `--format` includes `3mf` or `obj`.

## Black top-cap behavior

If you add `--color-letters`, the script makes the top `0.2 mm` of the raised letters black in 3MF and OBJ exports.

If you add `--color-border`, the script makes the top `0.2 mm` of the raised border black in 3MF and OBJ exports.

If you use both flags, both cap areas become black.

When these color flags are active:

- the cap surfaces are black
- the rest of the colored model is white for better contrast
- STL stays unchanged and uncolored

For 3MF, the script writes explicit color resources into the file, so the black cap split stays exact.

For OBJ, the script writes one connected indexed mesh with inline vertex colors for better slicer compatibility.

The OBJ cap transition can show a slight color interpolation along the top `0.2 mm` sidewall because the mesh stays connected instead of being exported as stacked solids.

## Why the reference STL files still need text

The current script uses the raised sample text in the reference STL files to recover the safe text area automatically.

That means blank STL templates are not a drop-in replacement today.

If the reference STL files were blank, the current loader would lose the text placement guide and would need a different source of truth for the text bounds.

## File-name safety

The script makes a safe slug from the plant name:

- lowercase letters are used
- accents are simplified where possible
- spaces and punctuation become hyphens
- repeated hyphens are collapsed

Example:

```text
Héllo / Plant --- '' -> hello-plant
```

If a batch contains names that normalize to the same slug, the script numbers later ones:

```text
Hello Plant -> hello-plant
Hello / Plant -> hello-plant-2
```

## Long names

The script tries a one-line layout and multiple two-line layouts.

If the name would become too small to print clearly:

- in single-name mode, the script stops with a clear error
- in batch mode, that line is reported as failed and the rest of the batch continues
