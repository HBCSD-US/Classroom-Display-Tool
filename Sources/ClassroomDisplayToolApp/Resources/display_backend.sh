#!/bin/sh
set -eu

# Backend for the HBCSD Classroom Display Tool native app.
# POSIX sh is used intentionally so the tool works on stock macOS regardless
# of whether the user's login shell is zsh, bash, or something else.

TARGET_RESOLUTION="${TARGET_RESOLUTION-}"
LOG_DIR="${HOME}/Library/Logs/HBCSD Display Mirror"
LOG_FILE="${LOG_DIR}/display-config.log"

SCRIPT_DIR="$(CDPATH= cd "$(dirname "$0")" && pwd -P)"

usage() {
  cat <<'USAGE'
Usage:
  display_backend.sh --ui-state
  display_backend.sh --ui-apply mirror|private|extend
  display_backend.sh --diagnose

Presets:
  mirror       Mirror Everything
  private      Teacher Private Mode
  extend       Extend All Displays
  diagnose     Diagnose Displays without changing settings

Optional environment:
  TARGET_RESOLUTION=1920x1080  Force a specific mirror resolution.
USAGE
}

log_line() {
  mkdir -p "$LOG_DIR"
  printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG_FILE"
}

say() {
  printf '%s\n' "$*"
  log_line "$*"
}

die() {
  say "Error: $*"
  exit 1
}

find_executable() {
  name="$1"

  if command -v "$name" >/dev/null 2>&1; then
    command -v "$name"
    return 0
  fi

  for candidate in "/opt/homebrew/bin/$name" "/usr/local/bin/$name"; do
    if [ -x "$candidate" ]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  return 1
}

find_displayplacer() {
  arch="$(uname -m)"

  for candidate in \
    "$SCRIPT_DIR/bin/displayplacer-$arch" \
    "$SCRIPT_DIR/bin/displayplacer" \
    "/Applications/HBCSD Classroom Display Tool.app/Contents/Resources/bin/displayplacer-$arch" \
    "/Applications/HBCSD Classroom Display Tool.app/Contents/Resources/bin/displayplacer"; do
    if [ -x "$candidate" ]; then
      xattr -d com.apple.quarantine "$candidate" >/dev/null 2>&1 || true
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  find_executable displayplacer
}

displayplacer_bin="$(find_displayplacer || true)"
if [ -z "$displayplacer_bin" ]; then
  die "displayplacer was not found. Reinstall the tool or keep the bundled bin folder next to this script."
fi

tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/classroom-display.XXXXXX")"
cleanup() {
  rm -rf "$tmpdir"
}
trap cleanup 0 1 2 15

displayplacer_file="$tmpdir/displayplacer-list.txt"
system_profiler_file="$tmpdir/system-profiler.txt"
records_file="$tmpdir/display-records.txt"
names_file="$tmpdir/display-names.txt"
inventory_file="$tmpdir/display-inventory.txt"
enabled_file="$tmpdir/enabled-displays.txt"
available_file="$tmpdir/available-actions.txt"
source_file="$tmpdir/classroom-source.txt"
source_ranking_file="$tmpdir/source-ranking.txt"
resolution_choice_file="$tmpdir/resolution-choice.txt"
command_file="$tmpdir/displayplacer-command.txt"
fallback_command_file="$tmpdir/displayplacer-fallback-command.txt"
apply_output="$tmpdir/apply-output.txt"
verify_file="$tmpdir/verify.txt"
verify_warnings_file="$tmpdir/verify-warnings.txt"
diagnose_file="$tmpdir/diagnose.txt"
plan_file="$tmpdir/display-plan.txt"

display_count=0
builtin_count=0
external_count=0

preset_label() {
  case "$1" in
    mirror) printf '%s\n' "Mirror Everything" ;;
    private) printf '%s\n' "Teacher Private Mode" ;;
    extend) printf '%s\n' "Extend All Displays" ;;
    diagnose) printf '%s\n' "Diagnose Displays" ;;
    *) printf '%s\n' "$1" ;;
  esac
}

preset_description() {
  case "$1" in
    mirror) printf '%s\n' "All detected displays show the same content." ;;
    private) printf '%s\n' "Built-in display stays private; classroom displays show shared content." ;;
    extend) printf '%s\n' "All displays stay separate, with the built-in display as main when present." ;;
    diagnose) printf '%s\n' "Shows detected displays, aspect ratios, and selected classroom source without changing settings." ;;
  esac
}

parse_displayplacer_records() {
  awk '
    function emit() {
      if (id != "") {
        idx++
        print idx "|" id "|" contextual "|" serial "|" type "|" resolution "|" hertz "|" depth "|" scaling "|" origin "|" degree "|" enabled "|" main "|" modes
      }
    }
    function reset_record() {
      contextual = ""; serial = ""; type = ""; resolution = ""; hertz = ""; depth = ""
      scaling = "off"; origin = "(0,0)"; degree = "0"; enabled = ""; main = "false"; modes = ""
    }
    function append_mode(line, mode_line, pieces, mode_num, res_value, mode_scaling, current, sep) {
      mode_line = line
      sub(/^[[:space:]]+mode /, "", mode_line)
      split(mode_line, pieces, ":")
      mode_num = pieces[1] + 0

      res_value = line
      sub(/^.* res:/, "", res_value)
      sub(/[[:space:]].*$/, "", res_value)
      if (res_value !~ /^[0-9]+x[0-9]+$/) {
        return
      }

      mode_scaling = "off"
      if (line ~ /scaling:on/) {
        mode_scaling = "on"
      }
      current = (line ~ /<-- current mode/ ? "current" : "")

      sep = (modes == "" ? "" : ";")
      modes = modes sep mode_num ":" res_value ":" mode_scaling ":" current
    }
    /^Persistent screen id:/ {
      emit()
      id = $0
      sub(/^Persistent screen id: /, "", id)
      reset_record()
      next
    }
    /^Contextual screen id:/ {
      contextual = $0
      sub(/^Contextual screen id: /, "", contextual)
      next
    }
    /^Serial screen id:/ {
      serial = $0
      sub(/^Serial screen id: /, "", serial)
      next
    }
    /^Type:/ {
      type = $0
      sub(/^Type: /, "", type)
      next
    }
    /^Resolution:/ {
      resolution = $0
      sub(/^Resolution: /, "", resolution)
      next
    }
    /^Hertz:/ {
      hertz = $0
      sub(/^Hertz: /, "", hertz)
      next
    }
    /^Color Depth:/ {
      depth = $0
      sub(/^Color Depth: /, "", depth)
      next
    }
    /^Scaling:/ {
      scaling = $0
      sub(/^Scaling: /, "", scaling)
      next
    }
    /^Origin:/ {
      origin = $0
      sub(/^Origin: /, "", origin)
      if (origin ~ /main display/) {
        main = "true"
      }
      sub(/ - main display$/, "", origin)
      next
    }
    /^Rotation:/ {
      degree = $0
      sub(/^Rotation: /, "", degree)
      sub(/ .*/, "", degree)
      next
    }
    /^Enabled:/ {
      enabled = $0
      sub(/^Enabled: /, "", enabled)
      next
    }
    /^[[:space:]]+mode [0-9]+:/ {
      append_mode($0)
      next
    }
    END {
      emit()
    }
  ' "$displayplacer_file" > "$records_file"
}

parse_system_profiler_records() {
  awk '
    function emit() {
      if (name != "") {
        idx++
        print idx "|" name "|" internal "|" connection "|" system_resolution "|" system_main "|" system_mirror
      }
    }
    function reset_record() {
      internal = "false"; connection = ""; system_resolution = ""; system_main = ""; system_mirror = ""
    }
    /^[[:space:]]{8}[^ ].*:$/ {
      emit()
      name = $0
      sub(/^[[:space:]]+/, "", name)
      sub(/:$/, "", name)
      reset_record()
      next
    }
    /Display Type: Built-in/ {
      internal = "true"
      next
    }
    /^[[:space:]]+Connection Type:/ {
      connection = $0
      sub(/^[[:space:]]+Connection Type:[[:space:]]*/, "", connection)
      if (connection == "Internal") {
        internal = "true"
      }
      next
    }
    /^[[:space:]]+Resolution:/ {
      system_resolution = $0
      sub(/^[[:space:]]+Resolution:[[:space:]]*/, "", system_resolution)
      gsub(/[[:space:]]+x[[:space:]]+/, "x", system_resolution)
      sub(/[[:space:]]+Retina.*$/, "", system_resolution)
      next
    }
    /^[[:space:]]+Main Display:/ {
      system_main = $0
      sub(/^[[:space:]]+Main Display:[[:space:]]*/, "", system_main)
      next
    }
    /^[[:space:]]+Mirror:/ {
      system_mirror = $0
      sub(/^[[:space:]]+Mirror:[[:space:]]*/, "", system_mirror)
      next
    }
    END {
      emit()
    }
  ' "$system_profiler_file" > "$names_file"
}

build_inventory_records() {
  record_count="$(wc -l < "$records_file" | tr -d ' ')"
  name_count="$(wc -l < "$names_file" | tr -d ' ')"
  if [ "$record_count" != "$name_count" ]; then
    awk -F'|' '{ print $1 "||||||" }' "$records_file" > "$names_file"
  fi

  awk -F'|' '
    function abs(value) {
      return value < 0 ? -value : value
    }
    function is_close_169(width, height, ratio) {
      if (height <= 0) {
        return "false"
      }
      ratio = width / height
      return abs(ratio - (16 / 9)) <= 0.08 ? "true" : "false"
    }
    function best_169_mode(modes, list, parts, i, width, height, area, best_area, best_res) {
      best_area = -1
      best_res = ""
      split(modes, list, ";")
      for (i in list) {
        split(list[i], parts, ":")
        split(parts[2], dims, "x")
        width = dims[1] + 0
        height = dims[2] + 0
        area = width * height
        if (is_close_169(width, height) == "true" && area > best_area) {
          best_area = area
          best_res = parts[2]
        }
      }
      return best_res
    }
    function append_note(existing, note) {
      if (existing == "") {
        return note
      }
      return existing ", " note
    }
    function choose_profile(record_idx, type, preferred_external, i) {
      if (type ~ /MacBook built in screen/) {
        for (i = 1; i <= profile_count; i++) {
          if (profile_used[i] != "true" && profile_internal[i] == "true") {
            return i
          }
        }
      }

      preferred_external = (type ~ /external screen/ || type !~ /MacBook built in screen/)
      if (preferred_external) {
        for (i = 1; i <= profile_count; i++) {
          if (profile_used[i] != "true" && profile_internal[i] != "true") {
            return i
          }
        }
      }

      if (record_idx in profile_name && profile_used[record_idx] != "true") {
        return record_idx
      }

      for (i = 1; i <= profile_count; i++) {
        if (profile_used[i] != "true") {
          return i
        }
      }

      return record_idx
    }
    FNR == NR {
      profile_count++
      profile_order[profile_count] = $1
      profile_name[$1] = $2
      profile_internal[$1] = $3
      profile_connection[$1] = $4
      profile_resolution[$1] = $5
      profile_main[$1] = $6
      profile_mirror[$1] = $7
      names[$1] = $2
      internal[$1] = $3
      connection[$1] = $4
      system_resolution[$1] = $5
      system_main[$1] = $6
      system_mirror[$1] = $7
      next
    }
    {
      idx = $1
      id = $2
      contextual = $3
      serial = $4
      type = $5
      resolution = $6
      hertz = $7
      depth = $8
      scaling = $9
      origin = $10
      degree = $11
      enabled = $12
      main = $13
      modes = $14
      profile_idx = choose_profile(idx, type)
      profile_used[profile_idx] = "true"

      name = ((profile_idx in profile_name) ? profile_name[profile_idx] : "")
      is_internal = ((profile_idx in profile_internal) ? profile_internal[profile_idx] : "false")
      connection_type = ((profile_idx in profile_connection) ? profile_connection[profile_idx] : "")
      sys_main = ((profile_idx in profile_main) ? profile_main[profile_idx] : "")
      sys_mirror = ((profile_idx in profile_mirror) ? profile_mirror[profile_idx] : "")

      split(resolution, dims, "x")
      width = dims[1] + 0
      height = dims[2] + 0
      area = width * height
      aspect = (height > 0 ? sprintf("%.3f", width / height) : "unknown")
      close_169 = is_close_169(width, height)

      is_builtin = "false"
      note = ""
      if (type ~ /MacBook built in screen/) {
        is_builtin = "true"
        note = append_note(note, "displayplacer reports built-in MacBook screen")
      }
      if (type ~ /external screen/) {
        is_builtin = "false"
        note = append_note(note, "displayplacer reports external screen")
      }
      if (is_internal == "true") {
        is_builtin = "true"
        note = append_note(note, "system_profiler reports internal connection")
      }
      if (name ~ /Color LCD|Built-in Retina Display|Built-in Liquid Retina Display|Internal Display/) {
        is_builtin = "true"
        note = append_note(note, "built-in display name")
      }
      if (connection_type != "" && connection_type != "Internal") {
        is_builtin = "false"
        note = append_note(note, "system_profiler reports " connection_type " connection")
      }

      role = (is_builtin == "true" ? "builtin" : "external")
      if (role == "external") {
        note = append_note(note, "non-built-in active display")
      }
      if (close_169 == "true") {
        note = append_note(note, "close to 16:9")
      }

      stable = "false"
      if (connection_type ~ /HDMI|DisplayPort|Thunderbolt|USB|DVI|VGA/) {
        stable = "true"
      }

      source_score = 0
      if (role == "external") {
        source_score += 1000000
      }
      if (close_169 == "true") {
        source_score += 100000
      }
      if (stable == "true") {
        source_score += 10000
      }
      source_score += int(area / 100)

      print idx "|" id "|" contextual "|" serial "|" type "|" name "|" role "|" is_builtin "|" connection_type "|" resolution "|" width "|" height "|" aspect "|" close_169 "|" hertz "|" depth "|" scaling "|" origin "|" degree "|" enabled "|" main "|" modes "|" best_169_mode(modes) "|" area "|" source_score "|" note "|" sys_main "|" sys_mirror
    }
  ' "$names_file" "$records_file" > "$inventory_file"

  awk -F'|' '$20 == "true" { print }' "$inventory_file" > "$enabled_file"
}

rank_classroom_source() {
  : > "$source_file"
  : > "$source_ranking_file"

  awk -F'|' -v ranking="$source_ranking_file" -v source="$source_file" '
    {
      display_name = ($6 != "" ? $6 : "(unnamed display)")
      print "  - " display_name " [" $7 "] score=" $25 ", res=" $10 ", aspect=" $13 ", close_16_9=" $14 ", connection=" ($9 != "" ? $9 : "unknown") >> ranking
      if (best_idx == "" || ($25 + 0) > best_score) {
        best_idx = $1
        best_score = $25 + 0
      }
    }
    END {
      if (best_idx != "") {
        print best_idx > source
      }
    }
  ' "$enabled_file"
}

capture_display_data() {
  "$displayplacer_bin" list > "$displayplacer_file"
  system_profiler SPDisplaysDataType > "$system_profiler_file" 2>/dev/null || true

  parse_displayplacer_records
  parse_system_profiler_records
  build_inventory_records
  rank_classroom_source

  display_count="$(wc -l < "$enabled_file" | tr -d ' ')"
  builtin_count="$(awk -F'|' '$7 == "builtin" { count++ } END { print count + 0 }' "$enabled_file")"
  external_count="$(awk -F'|' '$7 == "external" { count++ } END { print count + 0 }' "$enabled_file")"
}

get_source_idx() {
  if [ -s "$source_file" ]; then
    sed -n '1p' "$source_file"
  else
    printf '%s\n' ""
  fi
}

record_field() {
  idx="$1"
  field="$2"
  awk -F'|' -v idx="$idx" -v field="$field" '$1 == idx { print $field; found = 1 } END { if (!found) print "" }' "$enabled_file"
}

source_field() {
  field="$1"
  source_idx="$(get_source_idx)"
  if [ -z "$source_idx" ]; then
    printf '%s\n' ""
    return 0
  fi
  record_field "$source_idx" "$field"
}

choose_extend_main_idx() {
  source_idx="$(get_source_idx)"
  awk -F'|' -v source_idx="$source_idx" '
    $7 == "builtin" && builtin == "" { builtin = $1 }
    $21 == "true" && current_main == "" { current_main = $1 }
    first == "" { first = $1 }
    END {
      if (builtin != "") {
        print builtin
      } else if (current_main != "") {
        print current_main
      } else if (source_idx != "") {
        print source_idx
      } else {
        print first
      }
    }
  ' "$enabled_file"
}

choose_external_source_idx() {
  source_idx="$(get_source_idx)"
  source_role=""
  if [ -n "$source_idx" ]; then
    source_role="$(record_field "$source_idx" 7)"
  fi

  if [ "$source_role" = "external" ]; then
    printf '%s\n' "$source_idx"
    return 0
  fi

  awk -F'|' '
    $7 == "external" {
      if (best_idx == "" || ($25 + 0) > best_score) {
        best_idx = $1
        best_score = $25 + 0
      }
    }
    END { print best_idx }
  ' "$enabled_file"
}

build_available_presets() {
  : > "$available_file"

  if [ "$display_count" -ge 2 ]; then
    printf '%s|%s|%s\n' "mirror" "$(preset_label mirror)" "$(preset_description mirror)" >> "$available_file"

    if [ "$builtin_count" -gt 0 ] && [ "$external_count" -gt 0 ]; then
      printf '%s|%s|%s\n' "private" "$(preset_label private)" "$(preset_description private)" >> "$available_file"
    fi

    if [ "$display_count" -ge 3 ]; then
      printf '%s|%s|%s\n' "extend" "$(preset_label extend)" "$(preset_description extend)" >> "$available_file"
    fi
  fi

  printf '%s|%s|%s\n' "diagnose" "$(preset_label diagnose)" "$(preset_description diagnose)" >> "$available_file"
}

display_summary() {
  source_idx="$(get_source_idx)"
  awk -F'|' -v source_idx="$source_idx" '
    BEGIN { print "Detected displays:" }
    {
      display_name = ($6 != "" ? $6 : "(unnamed display)")
      role = ($7 == "builtin" ? "built-in/private" : "classroom/external")
      main = ($21 == "true" ? ", current main" : "")
      source = ($1 == source_idx ? ", classroom source candidate" : "")
      connection = ($9 != "" ? ", " $9 : "")
      print "  - " display_name " (" role ", " $10 ", aspect " $13 connection main source ")"
    }
  ' "$enabled_file"
}

classroom_source_summary() {
  source_idx="$(get_source_idx)"
  if [ -z "$source_idx" ]; then
    printf '%s\n' "Classroom source candidate: none"
    return 0
  fi

  awk -F'|' -v source_idx="$source_idx" '
    $1 == source_idx {
      display_name = ($6 != "" ? $6 : "(unnamed display)")
      print "Classroom source candidate: " display_name " (" $7 ", " $10 ", aspect " $13 ", close_16_9=" $14 ")"
      print "Selection reason: " $26
    }
  ' "$enabled_file"
}

mirror_resolution_summary() {
  source_idx="$(get_source_idx)"
  if [ -z "$source_idx" ]; then
    printf '%s\n' "Mirror resolution candidate: none"
    return 0
  fi

  resolution="$(select_group_resolution "$source_idx")"
  scaling="$(resolution_choice_scaling)"
  reason="$(resolution_choice_reason)"

  printf 'Mirror resolution candidate: %s (scaling:%s)\n' "$resolution" "$scaling"
  printf 'Resolution candidate reason: %s\n' "$reason"
}

available_summary() {
  printf '%s\n' "Available actions:"
  awk -F'|' '{ print "  - " $2 ": " $3 }' "$available_file"
}

ui_text() {
  printf '%s' "$*" | tr '\n|' '  '
}

ui_value() {
  key="$1"
  shift
  printf '%s|%s\n' "$key" "$(ui_text "$*")"
}

external_connection_summary() {
  awk -F'|' '
    function label_for(connection, normalized) {
      normalized = toupper(connection)
      if (normalized ~ /AIRPLAY/) {
        return "AIRPLAY"
      }
      if (normalized ~ /HDMI/) {
        return "HDMI"
      }
      if (normalized ~ /DISPLAYPORT/) {
        return "DISPLAYPORT"
      }
      if (normalized ~ /THUNDERBOLT/) {
        return "THUNDERBOLT"
      }
      if (normalized ~ /USB/) {
        return "USB-C"
      }
      if (normalized ~ /VGA/) {
        return "VGA"
      }
      if (normalized ~ /DVI/) {
        return "DVI"
      }
      return ""
    }
    $7 == "external" {
      label = label_for($9)
      if (label != "" && seen[label] != "true") {
        seen[label] = "true"
        labels[++count] = label
      }
    }
    END {
      for (i = 1; i <= count; i++) {
        out = (out == "" ? labels[i] : out " + " labels[i])
      }
      print out
    }
  ' "$enabled_file"
}

ui_display_heading() {
  connection_summary="$(external_connection_summary)"
  suffix=""
  if [ -n "$connection_summary" ]; then
    suffix=" ($connection_summary)"
  fi

  case "$external_count" in
    0)
      printf '%s\n' "NO EXTERNAL DISPLAY DETECTED"
      ;;
    1)
      printf '%s\n' "ONE EXTERNAL DISPLAY$suffix"
      ;;
    2)
      printf '%s\n' "TWO EXTERNAL DISPLAYS$suffix"
      ;;
    *)
      printf '%s\n' "$external_count EXTERNAL DISPLAYS$suffix"
      ;;
  esac
}

print_ui_external_displays() {
  awk -F'|' '
    function clean(value) {
      gsub(/[|\r\n]/, " ", value)
      gsub(/^[[:space:]]+/, "", value)
      gsub(/[[:space:]]+$/, "", value)
      return value
    }
    function connection_label(connection, normalized) {
      normalized = toupper(connection)
      if (normalized ~ /AIRPLAY|WIRELESS/) {
        return "AirPlay"
      }
      if (normalized ~ /HDMI/) {
        return "HDMI"
      }
      if (normalized ~ /DISPLAYPORT/) {
        return "DisplayPort"
      }
      if (normalized ~ /THUNDERBOLT/) {
        return "Thunderbolt"
      }
      if (normalized ~ /USB/) {
        return "USB-C"
      }
      if (normalized ~ /VGA/) {
        return "VGA"
      }
      if (normalized ~ /DVI/) {
        return "DVI"
      }
      return clean(connection)
    }
    $7 == "external" {
      count++
      name = clean($6)
      if (name == "") {
        name = "External Display " count
      }
      label = connection_label($9)
      print "external_display|" name "|" label
    }
  ' "$enabled_file"
}

ui_message() {
  if [ "$display_count" -lt 2 ]; then
    printf '%s\n' "Only one display is connected. Connect a classroom display, projector, or Apple TV display before choosing a display mode."
  else
    printf '%s\n' "Select the setup that matches how you want to present."
  fi
}

ui_preset_image() {
  preset="$1"
  case "$preset" in
    mirror)
      if [ "$display_count" -ge 3 ]; then
        printf '%s\n' "3-display-mirror-everything.png"
      else
        printf '%s\n' "2-display-mirror-everything.png"
      fi
      ;;
    private)
      if [ "$display_count" -ge 3 ]; then
        printf '%s\n' "3-display-teacher-private-mode.png"
      else
        printf '%s\n' "2-display-teacher-private-mode.png"
      fi
      ;;
    extend)
      printf '%s\n' "3-display-extend-all.png"
      ;;
  esac
}

print_ui_state() {
  ui_value "status" "ok"
  ui_value "display_count" "$display_count"
  ui_value "builtin_count" "$builtin_count"
  ui_value "external_count" "$external_count"
  ui_value "display_heading" "$(ui_display_heading)"
  ui_value "message" "$(ui_message)"
  ui_value "log_file" "$LOG_FILE"
  print_ui_external_displays

  while IFS='|' read -r preset label description; do
    [ "$preset" != "diagnose" ] || continue
    image_name="$(ui_preset_image "$preset")"
    printf 'preset|%s|%s|%s|%s\n' "$(ui_text "$preset")" "$(ui_text "$label")" "$(ui_text "$description")" "$(ui_text "$image_name")"
  done < "$available_file"
}

ui_apply_preset() {
  preset="$1"
  case "$preset" in
    mirror|private|extend)
      ;;
    *)
      ui_value "status" "error"
      ui_value "message" "Unknown display mode: $preset"
      ui_value "log_file" "$LOG_FILE"
      return 2
      ;;
  esac

  if ! is_available_preset "$preset"; then
    ui_value "status" "unavailable"
    ui_value "message" "$(plain_unavailable_message "$preset")"
    ui_value "log_file" "$LOG_FILE"
    return 0
  fi

  ui_apply_output="$tmpdir/ui-apply-output.txt"

  set +e
  apply_preset "$preset" "0" > "$ui_apply_output" 2>&1
  apply_status=$?
  set -e

  if [ "$apply_status" -ne 0 ]; then
    ui_value "status" "error"
    ui_value "message" "The display mode could not be applied. IT can review the log for details."
    ui_value "log_file" "$LOG_FILE"
    return "$apply_status"
  fi

  if [ -s "$verify_warnings_file" ]; then
    warning_detail="$(sed -n '1p' "$verify_warnings_file")"
    ui_value "status" "warning"
    ui_value "message" "${warning_detail:-The display mode was applied, but verification did not match the expected state.}"
    ui_value "log_file" "$LOG_FILE"
    return 0
  fi

  ui_value "status" "ok"
  ui_value "message" "$(preset_label "$preset") was applied."
  ui_value "log_file" "$LOG_FILE"
}

log_inventory() {
  {
    printf '%s\n' "Display inventory:"
    display_summary
    classroom_source_summary
    printf '%s\n' "Classroom source ranking:"
    cat "$source_ranking_file"
    printf '%s\n' "Raw active display inventory:"
    awk -F'|' '
      {
        display_name = ($6 != "" ? $6 : "(unnamed display)")
        print "  - idx=" $1 ", id=" $2 ", name=" display_name ", role=" $7 ", res=" $10 ", width=" $11 ", height=" $12 ", aspect=" $13 ", close_16_9=" $14 ", main=" $21 ", connection=" ($9 != "" ? $9 : "unknown") ", modes=" ($22 != "" ? $22 : "none") ", notes=" $26
      }
    ' "$enabled_file"
  } | sed 's/^/INVENTORY /' >> "$LOG_FILE"
}

list_displays() {
  say "Using displayplacer: $displayplacer_bin"
  say "Enabled display count: $display_count"
  say "Built-in displays: $builtin_count"
  say "External displays: $external_count"
  display_summary | tee -a "$LOG_FILE"
  classroom_source_summary | tee -a "$LOG_FILE"
  mirror_resolution_summary | tee -a "$LOG_FILE"
  available_summary | tee -a "$LOG_FILE"
}

is_available_preset() {
  preset="$1"
  awk -F'|' -v preset="$preset" '$1 == preset { found = 1 } END { exit found ? 0 : 1 }' "$available_file"
}

select_group_resolution() {
  source_idx="$1"
  : > "$resolution_choice_file"

  awk -F'|' -v source_idx="$source_idx" -v target="$TARGET_RESOLUTION" '
    function abs(value) {
      return value < 0 ? -value : value
    }
    function is_close_169(resolution, dims, width, height, ratio) {
      split(resolution, dims, "x")
      width = dims[1] + 0
      height = dims[2] + 0
      if (height <= 0) {
        return 0
      }
      ratio = width / height
      return abs(ratio - (16 / 9)) <= 0.08
    }
    function mode_has_resolution(modes, wanted, list, parts, i) {
      split(modes, list, ";")
      for (i in list) {
        split(list[i], parts, ":")
        if (parts[2] == wanted) {
          return 1
        }
      }
      return 0
    }
    function scaling_for_resolution(modes, wanted, preferred, list, parts, i, fallback) {
      fallback = ""
      split(modes, list, ";")
      for (i in list) {
        split(list[i], parts, ":")
        if (parts[2] == wanted) {
          if (fallback == "") {
            fallback = parts[3]
          }
          if (parts[3] == preferred) {
            return parts[3]
          }
        }
      }
      if (fallback != "") {
        return fallback
      }
      return preferred
    }
    function best_close_mode(modes, list, parts, dims, i, width, height, area, diff, best_score, score, best_res) {
      best_score = -999999999
      best_res = ""
      best_scaling = ""
      split(modes, list, ";")
      for (i in list) {
        split(list[i], parts, ":")
        split(parts[2], dims, "x")
        width = dims[1] + 0
        height = dims[2] + 0
        if (height <= 0) {
          continue
        }
        diff = abs((width / height) - (16 / 9))
        if (diff <= 0.08) {
          area = width * height
          score = int(area / 100) - int(diff * 100000)
          if (parts[3] == "off") {
            score += 1
          }
          if (score > best_score) {
            best_score = score
            best_res = parts[2]
            best_scaling = parts[3]
          }
        }
      }
      if (best_res != "") {
        return best_res "|" best_scaling
      }
      return ""
    }
    $1 == source_idx {
      if (target != "") {
        print target "|" scaling_for_resolution($22, target, "off") "|TARGET_RESOLUTION override was provided"
        found = 1
        exit
      }
      if ($14 == "true" && $10 != "") {
        print $10 "|" scaling_for_resolution($22, $10, "off") "|source current resolution is close to 16:9"
        found = 1
        exit
      }
      if (mode_has_resolution($22, "1920x1080")) {
        print "1920x1080|" scaling_for_resolution($22, "1920x1080", "off") "|source offers 1920x1080"
        found = 1
        exit
      }
      if (mode_has_resolution($22, "3840x2160")) {
        print "3840x2160|" scaling_for_resolution($22, "3840x2160", "off") "|source offers 3840x2160"
        found = 1
        exit
      }
      best = best_close_mode($22)
      if (best != "") {
        print best "|source offers a close 16:9 mode"
        found = 1
        exit
      }
      print $10 "|" scaling_for_resolution($22, $10, "off") "|using source current resolution because no 16:9 mode was found"
      found = 1
      exit
    }
    END {
      if (!found) {
        print "1920x1080|off|fallback resolution because no source display was found"
      }
    }
  ' "$enabled_file" > "$resolution_choice_file"

  awk -F'|' '{ print $1; exit }' "$resolution_choice_file"
}

resolution_choice_reason() {
  awk -F'|' '{ print $3; exit }' "$resolution_choice_file"
}

resolution_choice_scaling() {
  awk -F'|' '{ print $2; exit }' "$resolution_choice_file"
}

display_arg() {
  id="$1"
  resolution="$2"
  scaling="$3"
  origin="$4"
  degree="$5"

  if [ -z "$scaling" ]; then
    scaling="off"
  fi

  printf 'id:%s res:%s enabled:true scaling:%s origin:%s degree:%s\n' "$id" "$resolution" "$scaling" "$origin" "$degree"
}

display_mode_arg() {
  id="$1"
  mode="$2"
  origin="$3"
  degree="$4"

  printf 'id:%s mode:%s origin:%s degree:%s\n' "$id" "$mode" "$origin" "$degree"
}

append_display_record_arg() {
  idx="$1"
  origin="$2"
  outfile="$3"

  awk -F'|' -v idx="$idx" -v origin="$origin" '
    function abs(value) {
      return value < 0 ? -value : value
    }
    function close_169(resolution, dims, width, height) {
      split(resolution, dims, "x")
      width = dims[1] + 0
      height = dims[2] + 0
      if (height <= 0) {
        return 0
      }
      return abs((width / height) - (16 / 9)) <= 0.08
    }
    function choose_mode_for_res(modes, resolution, preferred_scaling, list, parts, i, fallback) {
      fallback = ""
      split(modes, list, ";")
      for (i = 1; i <= length(list); i++) {
        split(list[i], parts, ":")
        if (parts[2] == resolution) {
          if (fallback == "") {
            fallback = parts[1]
          }
          if (parts[3] == preferred_scaling) {
            return parts[1]
          }
        }
      }
      return fallback
    }
    function choose_builtin_extend_res(current_res, modes, list, parts, dims, i, width, height, area, best_area, best_res) {
      if (!close_169(current_res)) {
        return current_res
      }

      split(modes, list, ";")
      for (i = 1; i <= length(list); i++) {
        split(list[i], parts, ":")
        if (parts[2] == "1470x956" && parts[3] == "on") {
          return parts[2]
        }
      }

      best_area = -1
      best_res = ""
      for (i = 1; i <= length(list); i++) {
        split(list[i], parts, ":")
        split(parts[2], dims, "x")
        width = dims[1] + 0
        height = dims[2] + 0
        area = width * height
        if (parts[3] == "on" && !close_169(parts[2]) && width <= 1800 && height <= 1200 && area > best_area) {
          best_area = area
          best_res = parts[2]
        }
      }
      if (best_res != "") {
        return best_res
      }

      for (i = 1; i <= length(list); i++) {
        split(list[i], parts, ":")
        if (parts[3] == "on" && !close_169(parts[2])) {
          return parts[2]
        }
      }

      return current_res
    }
    $1 == idx {
      resolution = $10
      scaling = $17
      if ($7 == "builtin") {
        resolution = choose_builtin_extend_res($10, $22)
        scaling = "on"
      }
      mode = choose_mode_for_res($22, resolution, scaling)
      print $2 "|" resolution "|" mode "|" scaling "|" origin "|" $19
    }
  ' "$enabled_file" | while IFS='|' read -r id resolution mode scaling arg_origin degree; do
    if [ -n "$mode" ]; then
      display_mode_arg "$id" "$mode" "$arg_origin" "$degree" >> "$outfile"
    else
      display_arg "$id" "$resolution" "$scaling" "$arg_origin" "$degree" >> "$outfile"
    fi
  done
}

record_plan() {
  preset="$1"
  layout="$2"
  source_idx="$3"
  main_idx="$4"
  resolution="$5"
  reason="$6"
  scaling="${7:-}"

  source_id="$(record_field "$source_idx" 2)"
  source_name="$(record_field "$source_idx" 6)"
  source_role="$(record_field "$source_idx" 7)"
  main_id="$(record_field "$main_idx" 2)"
  main_name="$(record_field "$main_idx" 6)"

  : > "$plan_file"
  printf 'preset|%s\n' "$preset" >> "$plan_file"
  printf 'layout|%s\n' "$layout" >> "$plan_file"
  printf 'display_count|%s\n' "$display_count" >> "$plan_file"
  printf 'source_idx|%s\n' "$source_idx" >> "$plan_file"
  printf 'source_id|%s\n' "$source_id" >> "$plan_file"
  printf 'source_name|%s\n' "${source_name:-"(unnamed display)"}" >> "$plan_file"
  printf 'source_role|%s\n' "$source_role" >> "$plan_file"
  printf 'main_idx|%s\n' "$main_idx" >> "$plan_file"
  printf 'main_id|%s\n' "$main_id" >> "$plan_file"
  printf 'main_name|%s\n' "${main_name:-"(unnamed display)"}" >> "$plan_file"
  printf 'resolution|%s\n' "$resolution" >> "$plan_file"
  printf 'resolution_scaling|%s\n' "$scaling" >> "$plan_file"
  printf 'resolution_reason|%s\n' "$reason" >> "$plan_file"
}

plan_value() {
  key="$1"
  awk -F'|' -v key="$key" '$1 == key { print $2; found = 1 } END { if (!found) print "" }' "$plan_file"
}

plan_summary() {
  printf '%s\n' "Display plan:"
  printf '  Preset: %s\n' "$(preset_label "$(plan_value preset)")"
  printf '  Layout: %s\n' "$(plan_value layout)"
  printf '  Main display target: %s\n' "$(plan_value main_name)"
  printf '  Classroom source target: %s (%s)\n' "$(plan_value source_name)" "$(plan_value source_role)"
  printf '  Mirror/classroom resolution: %s\n' "$(plan_value resolution)"
  if [ -n "$(plan_value resolution_scaling)" ]; then
    printf '  Mirror/classroom scaling: %s\n' "$(plan_value resolution_scaling)"
  fi
  printf '  Resolution reason: %s\n' "$(plan_value resolution_reason)"
}

build_extend_command() {
  outfile="$1"
  : > "$outfile"

  main_idx="$(choose_extend_main_idx)"
  if [ -z "$main_idx" ]; then
    return 1
  fi

  awk -F'|' -v main_idx="$main_idx" '
    function abs(value) {
      return value < 0 ? -value : value
    }
    function close_169(resolution, dims, width, height) {
      split(resolution, dims, "x")
      width = dims[1] + 0
      height = dims[2] + 0
      if (height <= 0) {
        return 0
      }
      return abs((width / height) - (16 / 9)) <= 0.08
    }
    function width_of(res, parts) {
      split(res, parts, "x")
      return parts[1] + 0
    }
    function choose_builtin_extend_res(current_res, modes, list, parts, dims, i, width, height, area, best_area, best_res) {
      if (!close_169(current_res)) {
        return current_res
      }

      split(modes, list, ";")
      for (i = 1; i <= length(list); i++) {
        split(list[i], parts, ":")
        if (parts[2] == "1470x956" && parts[3] == "on") {
          return parts[2]
        }
      }

      best_area = -1
      best_res = ""
      for (i = 1; i <= length(list); i++) {
        split(list[i], parts, ":")
        split(parts[2], dims, "x")
        width = dims[1] + 0
        height = dims[2] + 0
        area = width * height
        if (parts[3] == "on" && !close_169(parts[2]) && width <= 1800 && height <= 1200 && area > best_area) {
          best_area = area
          best_res = parts[2]
        }
      }
      if (best_res != "") {
        return best_res
      }

      for (i = 1; i <= length(list); i++) {
        split(list[i], parts, ":")
        if (parts[3] == "on" && !close_169(parts[2])) {
          return parts[2]
        }
      }

      return current_res
    }
    {
      ids[NR] = $2
      resolutions[NR] = $10
      arranged_resolutions[NR] = ($7 == "builtin" ? choose_builtin_extend_res($10, $22) : $10)
      degrees[NR] = $19
      widths[NR] = $11
      indexes[NR] = $1
      if ($1 == main_idx) {
        main_row = NR
      }
    }
    END {
      if (NR == 0 || main_row == 0) {
        exit 1
      }

      order_count = 1
      order[order_count] = main_row
      for (i = 1; i <= NR; i++) {
        if (i != main_row) {
          order_count++
          order[order_count] = i
        }
      }

      x = 0
      for (i = 1; i <= order_count; i++) {
        row = order[i]
        origin = "(" x ",0)"
        print indexes[row] "|" origin
        x += width_of(arranged_resolutions[row])
      }
    }
  ' "$enabled_file" | while IFS='|' read -r idx origin; do
    append_display_record_arg "$idx" "$origin" "$outfile"
  done

  source_idx="$(get_source_idx)"
  record_plan "extend" "extend_all" "$source_idx" "$main_idx" "$(record_field "$main_idx" 10)" "extended displays use safe current or built-in-friendly modes"
}

build_mirror_all_command() {
  outfile="$1"
  : > "$outfile"

  source_idx="$(get_source_idx)"
  if [ -z "$source_idx" ]; then
    return 1
  fi

  resolution="$(select_group_resolution "$source_idx")"
  scaling="$(resolution_choice_scaling)"
  reason="$(resolution_choice_reason)"

  mirror_ids="$(awk -F'|' -v source_idx="$source_idx" '
    $1 == source_idx {
      source_id = $2
    }
    {
      ids[NR] = $2
      indexes[NR] = $1
    }
    END {
      if (source_id == "") {
        exit 1
      }
      output = source_id
      for (i = 1; i <= NR; i++) {
        if (indexes[i] != source_idx) {
          output = output "+" ids[i]
        }
      }
      print output
    }
  ' "$enabled_file")"

  printf 'id:%s res:%s enabled:true scaling:%s origin:(0,0) degree:0\n' "$mirror_ids" "$resolution" "$scaling" > "$outfile"
  record_plan "mirror" "mirror_all" "$source_idx" "$source_idx" "$resolution" "$reason" "$scaling"
}

build_private_command() {
  outfile="$1"
  : > "$outfile"

  if [ "$builtin_count" -eq 0 ] || [ "$external_count" -eq 0 ]; then
    return 1
  fi

  if [ "$external_count" -eq 1 ]; then
    build_extend_command "$outfile"
    record_plan "private" "builtin_private_extended" "$(choose_external_source_idx)" "$(choose_extend_main_idx)" "$(source_field 10)" "single external display stays extended"
    return 0
  fi

  builtin_idx="$(awk -F'|' '$7 == "builtin" { print $1; exit }' "$enabled_file")"
  external_source_idx="$(choose_external_source_idx)"
  if [ -z "$builtin_idx" ] || [ -z "$external_source_idx" ]; then
    return 1
  fi

  builtin_width="$(record_field "$builtin_idx" 11)"

  append_display_record_arg "$builtin_idx" "(0,0)" "$outfile"

  resolution="$(select_group_resolution "$external_source_idx")"
  scaling="$(resolution_choice_scaling)"
  reason="$(resolution_choice_reason)"
  external_ids="$(awk -F'|' -v source_idx="$external_source_idx" '
    $7 == "external" && $1 == source_idx { source_id = $2 }
    $7 == "external" {
      ids[++count] = $2
      indexes[count] = $1
    }
    END {
      if (source_id == "") {
        exit 1
      }
      output = source_id
      for (i = 1; i <= count; i++) {
        if (indexes[i] != source_idx) {
          output = output "+" ids[i]
        }
      }
      print output
    }
  ' "$enabled_file")"

  printf 'id:%s res:%s enabled:true scaling:%s origin:(%s,0) degree:0\n' "$external_ids" "$resolution" "$scaling" "$builtin_width" >> "$outfile"
  record_plan "private" "builtin_private_external_mirror" "$external_source_idx" "$builtin_idx" "$resolution" "$reason" "$scaling"
}

build_command_for_preset() {
  preset="$1"
  outfile="$2"

  case "$preset" in
    mirror)
      if [ "$display_count" -lt 2 ]; then
        return 1
      fi
      build_mirror_all_command "$outfile"
      ;;
    extend)
      if [ "$display_count" -lt 3 ]; then
        return 1
      fi
      build_extend_command "$outfile"
      ;;
    private)
      build_private_command "$outfile"
      ;;
    *)
      return 1
      ;;
  esac
}

run_displayplacer_command() {
  infile="$1"

  set --
  while IFS= read -r arg; do
    [ -n "$arg" ] || continue
    set -- "$@" "$arg"
  done < "$infile"

  log_line "Generated displayplacer command:"
  sed 's/^/  /' "$infile" >> "$LOG_FILE"

  "$displayplacer_bin" "$@"
}

verify_preset_result() {
  : > "$verify_file"
  : > "$verify_warnings_file"

  planned_layout="$(plan_value layout)"
  planned_count="$(plan_value display_count)"
  planned_main_id="$(plan_value main_id)"
  planned_source_id="$(plan_value source_id)"
  planned_resolution="$(plan_value resolution)"
  planned_scaling="$(plan_value resolution_scaling)"

  capture_display_data
  build_available_presets

  {
    printf '%s\n' "Verification after apply:"
    display_summary
    classroom_source_summary
  } > "$verify_file"

  if [ "$display_count" != "$planned_count" ]; then
    printf 'Display count changed from %s to %s after applying the preset.\n' "$planned_count" "$display_count" >> "$verify_warnings_file"
  fi

  if [ -n "$planned_main_id" ]; then
    planned_main_state="$(awk -F'|' -v id="$planned_main_id" '$2 == id { print $21; found = 1 } END { if (!found) print "" }' "$enabled_file")"
    if [ "$planned_main_state" = "false" ]; then
      printf 'The expected main display was not reported as the main display after applying the preset.\n' >> "$verify_warnings_file"
    fi
  fi

  mirror_line_count="$(awk '/^[[:space:]]+Mirror:/ { count++ } END { print count + 0 }' "$system_profiler_file")"
  mirror_on_count="$(awk '/^[[:space:]]+Mirror:[[:space:]]+On/ { count++ } END { print count + 0 }' "$system_profiler_file")"

  case "$planned_layout" in
    mirror_all)
      if [ "$mirror_line_count" -gt 0 ] && [ "$mirror_on_count" -eq 0 ]; then
        printf 'macOS did not report the expected mirror state after Mirror Everything.\n' >> "$verify_warnings_file"
      fi
      if [ -n "$planned_source_id" ]; then
        planned_source_main="$(awk -F'|' -v id="$planned_source_id" '$2 == id { print $21; found = 1 } END { if (!found) print "" }' "$enabled_file")"
        if [ "$planned_source_main" = "false" ]; then
          printf 'The classroom source display was not reported as the main display after mirroring.\n' >> "$verify_warnings_file"
        fi
        planned_source_resolution="$(awk -F'|' -v id="$planned_source_id" '$2 == id { print $10; found = 1 } END { if (!found) print "" }' "$enabled_file")"
        planned_source_scaling="$(awk -F'|' -v id="$planned_source_id" '$2 == id { print $17; found = 1 } END { if (!found) print "" }' "$enabled_file")"
        if [ -n "$planned_resolution" ] && [ -n "$planned_source_resolution" ] && [ "$planned_source_resolution" != "$planned_resolution" ]; then
          printf 'The classroom source display reported resolution %s after mirroring, but %s was planned.\n' "$planned_source_resolution" "$planned_resolution" >> "$verify_warnings_file"
        fi
        if [ -n "$planned_scaling" ] && [ -n "$planned_source_scaling" ] && [ "$planned_source_scaling" != "$planned_scaling" ]; then
          printf 'The classroom source display reported scaling:%s after mirroring, but scaling:%s was planned.\n' "$planned_source_scaling" "$planned_scaling" >> "$verify_warnings_file"
        fi
      fi
      ;;
    extend_all|builtin_private_extended)
      if [ "$mirror_on_count" -gt 0 ]; then
        printf 'macOS still reports mirroring, but this preset expected extended displays.\n' >> "$verify_warnings_file"
      fi
      ;;
    builtin_private_external_mirror)
      if [ "$mirror_line_count" -gt 0 ] && [ "$mirror_on_count" -eq 0 ]; then
        printf 'macOS did not report the expected external-display mirror state.\n' >> "$verify_warnings_file"
      fi
      if [ -n "$planned_source_id" ]; then
        planned_source_resolution="$(awk -F'|' -v id="$planned_source_id" '$2 == id { print $10; found = 1 } END { if (!found) print "" }' "$enabled_file")"
        planned_source_scaling="$(awk -F'|' -v id="$planned_source_id" '$2 == id { print $17; found = 1 } END { if (!found) print "" }' "$enabled_file")"
        if [ -n "$planned_resolution" ] && [ -n "$planned_source_resolution" ] && [ "$planned_source_resolution" != "$planned_resolution" ]; then
          printf 'The classroom source display reported resolution %s after mirroring, but %s was planned.\n' "$planned_source_resolution" "$planned_resolution" >> "$verify_warnings_file"
        fi
        if [ -n "$planned_scaling" ] && [ -n "$planned_source_scaling" ] && [ "$planned_source_scaling" != "$planned_scaling" ]; then
          printf 'The classroom source display reported scaling:%s after mirroring, but scaling:%s was planned.\n' "$planned_source_scaling" "$planned_scaling" >> "$verify_warnings_file"
        fi
      fi
      ;;
  esac

  cat "$verify_file"
  sed 's/^/VERIFY /' "$verify_file" >> "$LOG_FILE"

  if [ -s "$verify_warnings_file" ]; then
    sed 's/^/VERIFY WARNING /' "$verify_warnings_file" >> "$LOG_FILE"
    return 1
  fi

  return 0
}

plain_unavailable_message() {
  preset="$1"
  if [ "$display_count" -lt 2 ]; then
    case "$preset" in
      mirror)
        printf '%s\n' "Only one display is connected, so there is nothing to mirror."
        ;;
      *)
        printf '%s\n' "Only one display is connected. Connect a classroom display, projector, or Apple TV display before choosing a display preset."
        ;;
    esac
    return 0
  fi

  case "$preset" in
    private)
      printf '%s\n' "Teacher Private Mode needs a built-in MacBook display and at least one classroom display. I could not detect that combination."
      ;;
    extend)
      printf '%s\n' "Extend All Displays is only shown when three or more displays are connected. With two displays, use Teacher Private Mode."
      ;;
    *)
      printf '%s\n' "$(preset_label "$preset") is not available for the current display setup."
      ;;
  esac
}

show_dialog() {
  message="$1"
  osascript \
    -e 'on run argv' \
    -e 'display dialog (item 1 of argv) buttons {"OK"} default button "OK" with title "HBCSD Display Setup"' \
    -e 'end run' \
    "$message" >/dev/null 2>&1 || true
}

choose_preset_dialog() {
  prompt="Choose a classroom display action:"
  if [ "$display_count" -lt 2 ]; then
    prompt="Only one display was detected. Diagnose Displays is available, but display presets need a classroom display."
  fi

  labels="$(awk -F'|' '{ if (out == "") out = "\"" $2 "\""; else out = out ", \"" $2 "\"" } END { print out }' "$available_file")"

  osascript <<EOF 2>/dev/null || printf '%s\n' "false"
set presetChoice to choose from list {$labels} with title "HBCSD Display Setup" with prompt "$prompt" OK button name "Apply" cancel button name "Cancel"
if presetChoice is false then
  return "false"
else
  return item 1 of presetChoice
end if
EOF
}

preset_from_label() {
  label="$1"
  awk -F'|' -v label="$label" '$2 == label { print $1; exit }' "$available_file"
}

diagnose_displays() {
  interactive="$1"

  {
    printf '%s\n' "Display diagnosis:"
    printf '  Enabled displays: %s\n' "$display_count"
    printf '  Built-in displays: %s\n' "$builtin_count"
    printf '  External displays: %s\n' "$external_count"
    printf '\n'
    display_summary
    printf '\n'
    classroom_source_summary
    printf '\n'
    mirror_resolution_summary
    printf '\n'
    printf '%s\n' "Classroom source ranking:"
    cat "$source_ranking_file"
    printf '\n'
    available_summary
    printf '\n'
    printf 'Log file: %s\n' "$LOG_FILE"
  } > "$diagnose_file"

  cat "$diagnose_file"
  sed 's/^/DIAGNOSE /' "$diagnose_file" >> "$LOG_FILE"

  if [ "$interactive" = "1" ]; then
    source_line="$(classroom_source_summary | sed -n '1p')"
    message="Detected $display_count display(s).
Built-in displays: $builtin_count
External displays: $external_count

$source_line

No display settings were changed.

Full details were logged at:
$LOG_FILE"
    show_dialog "$message"
  fi
}

apply_preset() {
  preset="$1"
  interactive="$2"
  label="$(preset_label "$preset")"

  if [ "$preset" = "diagnose" ]; then
    say "Selected action: $label"
    diagnose_displays "$interactive"
    return 0
  fi

  say "Selected preset: $label"
  list_displays

  if ! is_available_preset "$preset"; then
    message="$(plain_unavailable_message "$preset")"
    say "$message"
    if [ "$interactive" = "1" ]; then
      show_dialog "$message"
    fi
    return 0
  fi

  if ! build_command_for_preset "$preset" "$command_file"; then
    message="$(plain_unavailable_message "$preset")"
    say "$message"
    if [ "$interactive" = "1" ]; then
      show_dialog "$message"
    fi
    return 0
  fi

  plan_summary | tee -a "$LOG_FILE"

  say "Applying $label..."
  set +e
  run_displayplacer_command "$command_file" > "$apply_output" 2>&1
  apply_status=$?
  set -e

  if [ "$apply_status" -ne 0 ] && [ "$preset" = "private" ] && [ "$display_count" -ge 3 ]; then
    say "$label could not mirror the classroom displays. Falling back to Extend All Displays."
    cat "$apply_output" >> "$LOG_FILE"
    build_extend_command "$fallback_command_file"
    plan_summary | sed 's/^/FALLBACK /' | tee -a "$LOG_FILE"
    set +e
    run_displayplacer_command "$fallback_command_file" > "$apply_output" 2>&1
    apply_status=$?
    set -e
    fallback_used="1"
  else
    fallback_used="0"
  fi

  if [ -s "$apply_output" ]; then
    cat "$apply_output" >> "$LOG_FILE"
  fi

  if [ "$apply_status" -ne 0 ]; then
    message="The display preset could not be applied. No further changes were made by this tool. IT can review the log at:
$LOG_FILE"
    say "$message"
    if [ "$interactive" = "1" ]; then
      show_dialog "$message"
    fi
    return 1
  fi

  say "Applied display configuration."
  say "Verification:"
  if verify_preset_result; then
    verify_ok="1"
  else
    verify_ok="0"
  fi

  if [ "$verify_ok" = "0" ]; then
    warning_detail="$(sed -n '1p' "$verify_warnings_file")"
    message="$label was applied, but macOS did not report the expected display state.

${warning_detail:-Display verification did not match the expected preset.}

The displays may need to be reconnected or this preset may not be supported by the current setup. IT can review the log at:
$LOG_FILE"
  elif [ "$fallback_used" = "1" ]; then
    message="Classroom displays could not be mirrored together, so I used Extend All Displays instead.

The displays should still be usable for teaching. IT can review the log at:
$LOG_FILE"
  else
    message="$label was applied.

The displays should now be ready. IT can review the log at:
$LOG_FILE"
  fi

  if [ "$interactive" = "1" ]; then
    show_dialog "$message"
  fi
}

main() {
  capture_display_data
  build_available_presets

  log_line "----- HBCSD display tool run -----"
  log_line "displayplacer=$displayplacer_bin display_count=$display_count builtin_count=$builtin_count external_count=$external_count"
  log_inventory

  case "${1:-}" in
    "")
      selected_label="$(choose_preset_dialog)"
      if [ "$selected_label" = "false" ]; then
        say "No display changes were applied."
        exit 0
      fi
      selected_preset="$(preset_from_label "$selected_label")"
      if [ -z "$selected_preset" ]; then
        die "Could not map selected action: $selected_label"
      fi
      apply_preset "$selected_preset" "1"
      ;;
    --list)
      list_displays
      ;;
    --diagnose)
      diagnose_displays "0"
      ;;
    --ui-state)
      print_ui_state
      ;;
    --ui-apply)
      preset="${2:-}"
      ui_apply_preset "$preset"
      ;;
    --preset)
      preset="${2:-}"
      case "$preset" in
        mirror|private|extend|diagnose)
          apply_preset "$preset" "0"
          ;;
        *)
          usage
          exit 2
          ;;
      esac
      ;;
    --help|-h)
      usage
      ;;
    *)
      usage
      exit 2
      ;;
  esac
}

main "$@"
