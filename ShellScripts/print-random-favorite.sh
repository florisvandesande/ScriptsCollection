#!/usr/bin/env bash
set -euo pipefail

# === USER CONFIG ===
# Leave empty to use the macOS default printer.
PRINTER_NAME=""
# Folder where exported photos are stored before/after printing.
EXPORT_DIR="$HOME/Pictures/PrintedFavorites"
# Base folder for temporary run data.
TMP_BASE_DIR="${TMPDIR:-/tmp}"
# true: keep exported photos in EXPORT_DIR, false: remove after successful print.
KEEP_EXPORTED_FILES="true"
# Named printer preset to apply from the printer PPD.
PRINT_PRESET_NAME="Photo on Plain paper"
# true: fail if PRINT_PRESET_NAME cannot be found for the selected printer.
PRESET_REQUIRED="true"
# 13x18 cm on Epson drivers is commonly EPPhotoPaper2L (5x7 in).
TARGET_PAGE_SIZE_CODE="EPPhotoPaper2L"
# Target print size used for center-crop fill behavior.
TARGET_PAGE_WIDTH_CM="13"
TARGET_PAGE_HEIGHT_CM="18"
# Supported mode: auto-rotate-fill (rotate for best fit, then center-crop to fill).
FIT_MODE="auto-rotate-fill"
# === END USER CONFIG ===

die() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

info() {
  printf '%s\n' "$*"
}

trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

require_cmd() {
  local cmd="$1"
  command -v "$cmd" >/dev/null 2>&1 || die "Required command not found: $cmd"
}

is_positive_integer() {
  local value="$1"
  [[ "$value" =~ ^[0-9]+$ ]] && ((value > 0))
}

is_positive_number() {
  local value="$1"
  awk -v input="$value" '
    BEGIN {
      if (input ~ /^[0-9]+([.][0-9]+)?$/ && (input + 0) > 0) {
        exit 0
      }
      exit 1
    }'
}

is_truthy() {
  local value="${1:-}"
  value="$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]')"
  case "$value" in
    1|true|yes|y|on) return 0 ;;
    *) return 1 ;;
  esac
}

is_video_extension() {
  local ext
  ext="$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')"
  case "$ext" in
    mov|mp4|m4v|avi|mkv|mpg|mpeg|3gp|webm) return 0 ;;
    *) return 1 ;;
  esac
}

resolve_printer_name() {
  local configured default_line default_printer
  configured="$(trim "${PRINTER_NAME:-}")"

  if [[ -n "$configured" ]]; then
    lpstat -p "$configured" >/dev/null 2>&1 || die "Configured printer not found: $configured"
    printf '%s\n' "$configured"
    return
  fi

  if ! default_line="$(lpstat -d 2>/dev/null)"; then
    die "No default printer configured. Set PRINTER_NAME in the user config section."
  fi

  default_printer="$(trim "${default_line#*:}")"
  [[ -n "$default_printer" ]] || die "Could not determine default printer from: $default_line"
  lpstat -p "$default_printer" >/dev/null 2>&1 || die "Default printer is not available: $default_printer"
  printf '%s\n' "$default_printer"
}

resolve_ppd_path() {
  local printer="$1"
  local ppd_path="/etc/cups/ppd/${printer}.ppd"
  [[ -f "$ppd_path" ]] || die "Printer PPD file not found: $ppd_path"
  printf '%s\n' "$ppd_path"
}

validate_page_size_code() {
  local ppd_path="$1"
  local page_code="$2"

  awk -v code="$page_code" '
    $1 == "*PageSize" && $2 ~ ("^" code "/") { found = 1 }
    END { exit(found ? 0 : 1) }
  ' "$ppd_path" || die "Page size code \"$page_code\" is not supported by printer PPD: $ppd_path"
}

parse_preset_option_pairs() {
  local ppd_path="$1"
  local preset_name="$2"
  local awk_output=""
  local awk_status=0

  awk_output="$(
    awk -v target="$preset_name" '
      function trim(str) {
        sub(/^[[:space:]]+/, "", str)
        sub(/[[:space:]]+$/, "", str)
        return str
      }

      {
        if ($0 ~ /^\*OpenUI \*/) {
          line = $0
          sub(/^\*OpenUI \*/, "", line)
          sub(/\/.*/, "", line)
          sub(/:.*/, "", line)
          openui[line] = 1
        }

        if ($0 ~ /^\*APPrinterPreset /) {
          line = $0
          sub(/^\*APPrinterPreset [^\/]+\//, "", line)
          sub(/: "[[:space:]]*$/, "", line)
          if (line == target) {
            matched = 1
            in_preset = 1
            count = 0
          } else if (in_preset == 1) {
            in_preset = 0
          }
          next
        }

        if (in_preset == 1) {
          if ($0 ~ /^\*End[[:space:]]*$/) {
            in_preset = 0
            next
          }

          if ($0 ~ /^\*[^[:space:]]+[[:space:]]+/) {
            line = $0
            sub(/^\*/, "", line)

            key = line
            sub(/[[:space:]].*$/, "", key)

            val = line
            sub(/^[^[:space:]]+[[:space:]]+/, "", val)
            val = trim(val)

            if (key != "" && val != "") {
              count++
              keys[count] = key
              vals[count] = val
            }
          }
          next
        }
      }

      END {
        if (matched != 1) {
          exit 3
        }

        emitted = 0
        for (i = 1; i <= count; i++) {
          if (keys[i] in openui) {
            print keys[i] "=" vals[i]
            emitted++
          }
        }

        if (emitted == 0) {
          exit 4
        }
      }
    ' "$ppd_path" 2>&1
  )" || awk_status=$?

  if ((awk_status != 0)); then
    if ((awk_status == 3)); then
      die "Printer preset \"$preset_name\" not found in $ppd_path"
    elif ((awk_status == 4)); then
      die "Printer preset \"$preset_name\" was found but no usable options were extracted."
    fi
    die "Failed to parse printer preset \"$preset_name\": $awk_output"
  fi

  printf '%s\n' "$awk_output"
}

sanitize_for_filename() {
  local raw="$1"
  local safe
  safe="$(printf '%s' "$raw" | tr -cs '[:alnum:]._-' '_')"
  safe="${safe##_}"
  safe="${safe%%_}"
  [[ -n "$safe" ]] || safe="photo"
  printf '%s\n' "$safe"
}

file_extension_lower() {
  local file_path="$1"
  local ext
  ext="${file_path##*.}"
  if [[ "$ext" == "$file_path" ]]; then
    printf '%s\n' ""
    return
  fi
  printf '%s\n' "$(printf '%s' "$ext" | tr '[:upper:]' '[:lower:]')"
}

unique_output_path() {
  local dir="$1"
  local stem="$2"
  local ext="$3"
  local candidate idx

  if [[ -n "$ext" ]]; then
    candidate="$dir/${stem}.${ext}"
  else
    candidate="$dir/${stem}"
  fi

  idx=1
  while [[ -e "$candidate" ]]; do
    if [[ -n "$ext" ]]; then
      candidate="$dir/${stem}_${idx}.${ext}"
    else
      candidate="$dir/${stem}_${idx}"
    fi
    ((idx++))
  done

  printf '%s\n' "$candidate"
}

pick_exported_file() {
  local search_dir="$1"
  local path ext
  local -a preferred_files=()
  local -a fallback_files=()

  while IFS= read -r -d '' path; do
    ext="$(file_extension_lower "$path")"
    is_video_extension "$ext" && continue

    fallback_files+=("$path")
    case "$ext" in
      jpg|jpeg|png|heic|heif|tif|tiff|gif|bmp|webp)
        preferred_files+=("$path")
        ;;
    esac
  done < <(find "$search_dir" -type f -print0)

  if ((${#preferred_files[@]} > 0)); then
    printf '%s\n' "${preferred_files[0]}"
    return 0
  fi

  if ((${#fallback_files[@]} > 0)); then
    printf '%s\n' "${fallback_files[0]}"
    return 0
  fi

  return 1
}

get_image_dimensions_from_sips() {
  local image_file="$1"
  local metadata

  metadata="$(sips -g pixelWidth -g pixelHeight "$image_file" 2>/dev/null)" || return 1
  printf '%s\n' "$metadata" | awk '
    /pixelWidth:/  { width = $2 }
    /pixelHeight:/ { height = $2 }
    END {
      if (width ~ /^[0-9]+$/ && height ~ /^[0-9]+$/ && width > 0 && height > 0) {
        printf "%s\t%s\n", width, height
        exit 0
      }
      exit 1
    }'
}

best_fit_orientation() {
  local source_width="$1"
  local source_height="$2"
  local target_width_cm="$3"
  local target_height_cm="$4"

  awk \
    -v sw="$source_width" \
    -v sh="$source_height" \
    -v tw="$target_width_cm" \
    -v th="$target_height_cm" '
    function min(a, b) { return (a < b) ? a : b }
    function max(a, b) { return (a > b) ? a : b }
    BEGIN {
      sw += 0
      sh += 0
      tw += 0
      th += 0

      if (sw <= 0 || sh <= 0 || tw <= 0 || th <= 0) {
        print "portrait"
        exit 0
      }

      ratio_source = sw / sh
      ratio_portrait = min(tw, th) / max(tw, th)
      ratio_landscape = max(tw, th) / min(tw, th)

      keep_portrait = (ratio_source > ratio_portrait) ? (ratio_portrait / ratio_source) : (ratio_source / ratio_portrait)
      keep_landscape = (ratio_source > ratio_landscape) ? (ratio_landscape / ratio_source) : (ratio_source / ratio_landscape)

      if (keep_landscape > keep_portrait + 0.0000001) {
        print "landscape"
      } else if (keep_portrait > keep_landscape + 0.0000001) {
        print "portrait"
      } else if (sw >= sh) {
        print "landscape"
      } else {
        print "portrait"
      }
    }'
}

calculate_crop_dimensions() {
  local source_width="$1"
  local source_height="$2"
  local orientation="$3"
  local target_width_cm="$4"
  local target_height_cm="$5"

  awk \
    -v sw="$source_width" \
    -v sh="$source_height" \
    -v orientation="$orientation" \
    -v tw="$target_width_cm" \
    -v th="$target_height_cm" '
    function min(a, b) { return (a < b) ? a : b }
    function max(a, b) { return (a > b) ? a : b }
    BEGIN {
      sw += 0
      sh += 0
      tw += 0
      th += 0

      if (sw <= 0 || sh <= 0 || tw <= 0 || th <= 0) {
        exit 1
      }

      if (orientation == "landscape") {
        ratio_target = max(tw, th) / min(tw, th)
      } else {
        ratio_target = min(tw, th) / max(tw, th)
      }

      ratio_source = sw / sh

      if (ratio_source > ratio_target) {
        crop_w = int((sh * ratio_target) + 0.5)
        crop_h = sh
      } else {
        crop_w = sw
        crop_h = int((sw / ratio_target) + 0.5)
      }

      if (crop_w < 1) crop_w = 1
      if (crop_h < 1) crop_h = 1
      if (crop_w > sw) crop_w = sw
      if (crop_h > sh) crop_h = sh

      printf "%d\t%d\n", crop_w, crop_h
    }'
}

prepare_print_ready_file() {
  local source_file="$1"
  local source_width="$2"
  local source_height="$3"
  local temp_dir="$4"
  local fit_mode="$5"
  local target_width_cm="$6"
  local target_height_cm="$7"
  local ext working_file rotated_file ready_file orientation rotated
  local current_width current_height crop_line crop_width crop_height

  ext="$(file_extension_lower "$source_file")"
  [[ -n "$ext" ]] || ext="jpg"

  working_file="$temp_dir/print_working.$ext"
  cp "$source_file" "$working_file"

  if [[ "$fit_mode" == "auto-rotate-fill" ]]; then
    orientation="$(best_fit_orientation "$source_width" "$source_height" "$target_width_cm" "$target_height_cm")"
  else
    die "Unsupported FIT_MODE=\"$fit_mode\". Supported value: auto-rotate-fill"
  fi

  current_width="$source_width"
  current_height="$source_height"
  rotated="false"

  if [[ "$orientation" == "landscape" && "$current_width" -lt "$current_height" ]]; then
    rotated_file="$temp_dir/print_rotated.$ext"
    sips --rotate 90 "$working_file" --out "$rotated_file" >/dev/null 2>&1 || die "Failed to rotate image for landscape output."
    working_file="$rotated_file"
    current_width="$source_height"
    current_height="$source_width"
    rotated="true"
  elif [[ "$orientation" == "portrait" && "$current_width" -gt "$current_height" ]]; then
    rotated_file="$temp_dir/print_rotated.$ext"
    sips --rotate 90 "$working_file" --out "$rotated_file" >/dev/null 2>&1 || die "Failed to rotate image for portrait output."
    working_file="$rotated_file"
    current_width="$source_height"
    current_height="$source_width"
    rotated="true"
  fi

  crop_line="$(calculate_crop_dimensions "$current_width" "$current_height" "$orientation" "$target_width_cm" "$target_height_cm")" || die "Failed to compute crop dimensions."
  IFS=$'\t' read -r crop_width crop_height <<< "$crop_line"
  is_positive_integer "$crop_width" || die "Computed crop width is invalid: $crop_width"
  is_positive_integer "$crop_height" || die "Computed crop height is invalid: $crop_height"

  ready_file="$temp_dir/print_ready.$ext"
  sips -c "$crop_height" "$crop_width" "$working_file" --out "$ready_file" >/dev/null 2>&1 || die "Failed to crop image to target ratio."

  printf '%s\t%s\t%s\t%s\t%s\n' "$ready_file" "$orientation" "$rotated" "$crop_width" "$crop_height"
}

extract_job_id() {
  local lp_output="$1"
  if [[ "$lp_output" =~ request[[:space:]]id[[:space:]]is[[:space:]]([^[:space:]]+) ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
    return
  fi
  printf '%s\n' ""
}

print_with_color_fallback() {
  local printer="$1"
  local file="$2"
  shift 2
  local -a print_opts=("$@")
  local output err1 err2 err3

  if output="$(lp -d "$printer" "${print_opts[@]}" -o print-color-mode=color -- "$file" 2>&1)"; then
    printf '%s\n' "$output"
    return 0
  fi
  err1="$output"

  if output="$(lp -d "$printer" "${print_opts[@]}" -o ColorModel=Color -- "$file" 2>&1)"; then
    printf '%s\n' "$output"
    return 0
  fi
  err2="$output"

  if output="$(lp -d "$printer" "${print_opts[@]}" -- "$file" 2>&1)"; then
    printf '%s\n' "$output"
    return 0
  fi
  err3="$output"

  die "Unable to queue print job.
Attempt 1 (-o print-color-mode=color): $err1
Attempt 2 (-o ColorModel=Color): $err2
Attempt 3 (default options): $err3"
}

export_random_favorite() {
  local destination="$1"

  osascript - "$destination" <<'APPLESCRIPT'
on run argv
  if (count of argv) is not 1 then error "Missing export destination."
  set exportDir to item 1 of argv
  set tabChar to character id 9

  set videoExtensions to {"mov", "mp4", "m4v", "avi", "mkv", "mpg", "mpeg", "3gp", "webm"}
  set candidateItems to {}

  tell application "Photos"
    set favoriteItems to media items of favorites album
    if (count of favoriteItems) is 0 then error "No favorited media items found."

    repeat with itemRef in favoriteItems
      set itemFilename to filename of itemRef
      if itemFilename is missing value then set itemFilename to ""
      set itemExt to my lowercase_text(my file_extension(itemFilename))
      if itemExt is not in videoExtensions then set end of candidateItems to itemRef
    end repeat

    if (count of candidateItems) is 0 then error "No favorited photos found."

    set pickedItem to some item of candidateItems
    set pickedID to id of pickedItem
    set pickedFilename to filename of pickedItem
    set pickedWidth to width of pickedItem
    set pickedHeight to height of pickedItem
    if pickedWidth is missing value then set pickedWidth to 0
    if pickedHeight is missing value then set pickedHeight to 0
    export {pickedItem} to POSIX file exportDir
  end tell

  return pickedID & tabChar & pickedFilename & tabChar & (pickedWidth as text) & tabChar & (pickedHeight as text)
end run

on file_extension(fileName)
  if fileName is missing value then return ""
  set oldTID to AppleScript's text item delimiters
  set AppleScript's text item delimiters to "."
  set parts to text items of fileName
  set AppleScript's text item delimiters to oldTID
  if (count of parts) is less than 2 then return ""
  return item -1 of parts
end file_extension

on lowercase_text(inputText)
  return do shell script "printf %s " & quoted form of inputText & " | tr '[:upper:]' '[:lower:]'"
end lowercase_text
APPLESCRIPT
}

main() {
  local printer ppd_path resolved_line selected_id selected_name selected_width selected_height
  local export_file saved_file print_file orientation rotated_image crop_width crop_height
  local timestamp safe_id ext saved_stem print_result job_id
  local source_width source_height dims_line preset_output
  local -a preset_pairs=()
  local -a print_options=()
  local line

  require_cmd osascript
  require_cmd lp
  require_cmd lpstat
  require_cmd mktemp
  require_cmd find
  require_cmd sips
  require_cmd awk

  is_positive_number "$TARGET_PAGE_WIDTH_CM" || die "TARGET_PAGE_WIDTH_CM must be a positive number."
  is_positive_number "$TARGET_PAGE_HEIGHT_CM" || die "TARGET_PAGE_HEIGHT_CM must be a positive number."
  [[ -n "$(trim "$TARGET_PAGE_SIZE_CODE")" ]] || die "TARGET_PAGE_SIZE_CODE must not be empty."

  mkdir -p "$EXPORT_DIR" || die "Failed to create export directory: $EXPORT_DIR"
  mkdir -p "$TMP_BASE_DIR" || die "Failed to create temporary base directory: $TMP_BASE_DIR"

  printer="$(resolve_printer_name)"
  ppd_path="$(resolve_ppd_path "$printer")"
  validate_page_size_code "$ppd_path" "$TARGET_PAGE_SIZE_CODE"

  if [[ -n "$(trim "$PRINT_PRESET_NAME")" ]]; then
    preset_output="$(parse_preset_option_pairs "$ppd_path" "$PRINT_PRESET_NAME")"
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      preset_pairs+=("$line")
    done <<< "$preset_output"
  elif is_truthy "$PRESET_REQUIRED"; then
    die "PRESET_REQUIRED is true but PRINT_PRESET_NAME is empty."
  fi

  if is_truthy "$PRESET_REQUIRED" && ((${#preset_pairs[@]} == 0)); then
    die "No usable options found for required preset: $PRINT_PRESET_NAME"
  fi

  RUN_TMP_DIR="$(mktemp -d "$TMP_BASE_DIR/favorite-print.XXXXXX")"
  trap '[[ -n "${RUN_TMP_DIR:-}" && -d "$RUN_TMP_DIR" ]] && rm -rf "$RUN_TMP_DIR"' EXIT

  if ! resolved_line="$(export_random_favorite "$RUN_TMP_DIR" 2>&1)"; then
    die "Photos export failed: $resolved_line"
  fi

  resolved_line="${resolved_line%$'\n'}"
  resolved_line="${resolved_line//$'\r'/}"
  IFS=$'\t' read -r selected_id selected_name selected_width selected_height <<< "$resolved_line"
  [[ -n "${selected_id:-}" ]] || die "Unexpected response from Photos export."
  [[ -n "${selected_name:-}" ]] || selected_name="unknown"

  export_file="$(pick_exported_file "$RUN_TMP_DIR")" || die "No exported photo file was produced."

  timestamp="$(date '+%Y%m%d-%H%M%S')"
  safe_id="$(sanitize_for_filename "$selected_id")"
  ext="$(file_extension_lower "$export_file")"
  if [[ -z "$ext" ]]; then
    ext="$(file_extension_lower "$selected_name")"
  fi
  [[ -n "$ext" ]] || ext="jpg"

  saved_stem="${timestamp}_${safe_id}"
  saved_file="$(unique_output_path "$EXPORT_DIR" "$saved_stem" "$ext")"
  mv "$export_file" "$saved_file"

  source_width="$(trim "${selected_width:-}")"
  source_height="$(trim "${selected_height:-}")"
  if ! is_positive_integer "$source_width" || ! is_positive_integer "$source_height"; then
    dims_line="$(get_image_dimensions_from_sips "$saved_file")" || die "Failed to determine image dimensions."
    IFS=$'\t' read -r source_width source_height <<< "$dims_line"
  fi

  dims_line="$(prepare_print_ready_file "$saved_file" "$source_width" "$source_height" "$RUN_TMP_DIR" "$FIT_MODE" "$TARGET_PAGE_WIDTH_CM" "$TARGET_PAGE_HEIGHT_CM")"
  IFS=$'\t' read -r print_file orientation rotated_image crop_width crop_height <<< "$dims_line"
  [[ -f "$print_file" ]] || die "Failed to prepare print-ready file."

  for line in "${preset_pairs[@]}"; do
    print_options+=(-o "$line")
  done
  print_options+=(-o "media=$TARGET_PAGE_SIZE_CODE" -o "fit-to-page")
  if [[ "$orientation" == "landscape" ]]; then
    print_options+=(-o "orientation-requested=4")
  fi

  print_result="$(print_with_color_fallback "$printer" "$print_file" "${print_options[@]}")"
  job_id="$(extract_job_id "$print_result")"

  info "Selected Photos item ID: $selected_id"
  info "Original filename: $selected_name"
  info "Saved original file: $saved_file"
  info "Prepared print file: $print_file"
  info "Preset: $PRINT_PRESET_NAME"
  info "Target page size code: $TARGET_PAGE_SIZE_CODE (${TARGET_PAGE_WIDTH_CM}x${TARGET_PAGE_HEIGHT_CM} cm)"
  info "Prepared orientation: $orientation"
  info "Rotated for fit: $rotated_image"
  info "Crop size (pixels): ${crop_width}x${crop_height}"
  info "Printer: $printer"
  if [[ -n "$job_id" ]]; then
    info "Queued print job: $job_id"
  else
    info "Queued print job output: $print_result"
  fi

  if ! is_truthy "$KEEP_EXPORTED_FILES"; then
    rm -f "$saved_file"
    info "Removed exported file because KEEP_EXPORTED_FILES=$KEEP_EXPORTED_FILES"
  fi
}

main "$@"
