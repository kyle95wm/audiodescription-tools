#!/bin/bash

if [ -z "${BASH_VERSION:-}" ]; then
  exec /bin/bash "$0" "$@"
fi

set -euo pipefail

SCRIPT_VERSION="1.7.0"
# Set this to your raw GitHub script URL if you want a fixed update source.
# Example: https://raw.githubusercontent.com/owner/repo/main/cmp_video_v2.sh
DEFAULT_UPDATE_URL="https://raw.githubusercontent.com/kyle95wm/audiodescription-tools/refs/heads/main/audio_video_tools/cmp_video_v2.sh"
ORIGINAL_ARGS=("$@")
SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/${SCRIPT_NAME}"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}"
SETTINGS_FILE="${CONFIG_DIR}/cmp_video_v2.conf"

HEIGHT=720
INPUT=""
ENABLE_SMPTE=0
ORIGINAL_QUALITY=0
NO_PROXY_APPEND=0
PRESERVE_CONTAINER=0
AUTO_CONFIRM=0
DELETE_ORIGINAL=0
SELF_UPDATE_ONLY=0
SKIP_UPDATE=0
SHOW_HELP=0
INTERACTIVE_MODE=0
RECURSIVE=0
PREFLIGHT_PROCESS_COUNT=0
PREFLIGHT_SKIP_COUNT=0
INPUT_FILES=()
RESUME_FILE="${PWD}/.cmp_video_v2_resume"
RESUME_LOADED=0
RESUME_PATHS=()
RESUME_IDENTITIES=()
SAVED_SETTINGS_LOADED=0
SAVED_HEIGHT=720
SAVED_ENABLE_SMPTE=0
SAVED_ORIGINAL_QUALITY=0
SAVED_NO_PROXY_APPEND=0
SAVED_PRESERVE_CONTAINER=0
SAVED_AUTO_CONFIRM=0
SAVED_DELETE_ORIGINAL=0

is_bool_setting() {
  case "$1" in
    0|1)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

apply_saved_setting() {
  local key="$1"
  local value="$2"

  case "$key" in
    HEIGHT)
      if [ "$value" = "720" ] || [ "$value" = "1080" ]; then
        HEIGHT="$value"
        SAVED_HEIGHT="$value"
      fi
      ;;
    ENABLE_SMPTE)
      if is_bool_setting "$value"; then
        ENABLE_SMPTE="$value"
        SAVED_ENABLE_SMPTE="$value"
      fi
      ;;
    ORIGINAL_QUALITY)
      if is_bool_setting "$value"; then
        ORIGINAL_QUALITY="$value"
        SAVED_ORIGINAL_QUALITY="$value"
      fi
      ;;
    NO_PROXY_APPEND)
      if is_bool_setting "$value"; then
        NO_PROXY_APPEND="$value"
        SAVED_NO_PROXY_APPEND="$value"
      fi
      ;;
    PRESERVE_CONTAINER)
      if is_bool_setting "$value"; then
        PRESERVE_CONTAINER="$value"
        SAVED_PRESERVE_CONTAINER="$value"
      fi
      ;;
    AUTO_CONFIRM)
      if is_bool_setting "$value"; then
        AUTO_CONFIRM="$value"
        SAVED_AUTO_CONFIRM="$value"
      fi
      ;;
    DELETE_ORIGINAL)
      if is_bool_setting "$value"; then
        DELETE_ORIGINAL="$value"
        SAVED_DELETE_ORIGINAL="$value"
      fi
      ;;
  esac
}

load_saved_settings() {
  local line key value

  if [ ! -f "$SETTINGS_FILE" ]; then
    return
  fi

  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      ''|'#'*)
        continue
        ;;
    esac

    key="${line%%=*}"
    value="${line#*=}"

    if [ "$key" = "$line" ]; then
      continue
    fi

    apply_saved_setting "$key" "$value"
  done < "$SETTINGS_FILE"

  SAVED_SETTINGS_LOADED=1
}

load_saved_settings

for arg in "$@"; do
  case "$arg" in
    --fhd)
      HEIGHT=1080
      ;;
    --smpte)
      ENABLE_SMPTE=1
      ;;
    --original-quality)
      ORIGINAL_QUALITY=1
      ;;
    --no-proxy-append|--npa)
      NO_PROXY_APPEND=1
      ;;
    --preserve-container)
      PRESERVE_CONTAINER=1
      ;;
    --yes|--force)
      AUTO_CONFIRM=1
      ;;
    --delete-original|--delete-originals)
      DELETE_ORIGINAL=1
      ;;
    --interactive)
      INTERACTIVE_MODE=1
      ;;
    --self-update|--update)
      SELF_UPDATE_ONLY=1
      ;;
    --no-update|--skip-update)
      SKIP_UPDATE=1
      ;;
    -h|--help)
      SHOW_HELP=1
      ;;
    --all)
      INPUT="--all"
      ;;
    --recursive|-r)
      INPUT="--all"
      RECURSIVE=1
      ;;
    *)
      INPUT="$arg"
      ;;
  esac
done

resolve_update_url() {
  if [ -n "${CMP_VIDEO_UPDATE_URL:-}" ]; then
    echo "$CMP_VIDEO_UPDATE_URL"
    return
  fi

  if [ -n "$DEFAULT_UPDATE_URL" ]; then
    echo "$DEFAULT_UPDATE_URL"
    return
  fi

  local script_dir remote_url owner_repo default_branch
  script_dir="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"

  remote_url="$(git -C "$script_dir" config --get remote.origin.url 2>/dev/null || true)"
  if [ -z "$remote_url" ]; then
    return
  fi

  owner_repo="$(echo "$remote_url" | sed -E 's#^git@github.com:([^ ]+)\.git$#\1#; s#^https://github.com/([^ ]+)\.git$#\1#; s#^https://github.com/([^ ]+)$#\1#')"
  if [ -z "$owner_repo" ] || [ "$owner_repo" = "$remote_url" ]; then
    return
  fi

  default_branch="$(git -C "$script_dir" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##' || true)"
  if [ -z "$default_branch" ]; then
    default_branch="main"
  fi

  echo "https://raw.githubusercontent.com/${owner_repo}/${default_branch}/${SCRIPT_NAME}"
}

extract_version_from_file() {
  local file_path="$1"
  awk -F'"' '/^SCRIPT_VERSION="[0-9]+([.][0-9]+)*"/ { print $2; exit }' "$file_path" 2>/dev/null || true
}

is_newer_version() {
  local candidate="${1#v}"
  local current="${2#v}"

  awk -v candidate="$candidate" -v current="$current" '
    BEGIN {
      candidate_n = split(candidate, a, ".")
      current_n = split(current, b, ".")
      max_n = (candidate_n > current_n) ? candidate_n : current_n

      for (i = 1; i <= max_n; i++) {
        av = (i <= candidate_n) ? (a[i] + 0) : 0
        bv = (i <= current_n) ? (b[i] + 0) : 0
        if (av > bv) {
          print "1"
          exit
        }
        if (av < bv) {
          print "0"
          exit
        }
      }

      print "0"
    }
  '
}

install_updated_script() {
  local downloaded_file="$1"
  local backup_path

  backup_path="${SCRIPT_PATH}.bak"
  cp -f "$SCRIPT_PATH" "$backup_path"
  install -m 0755 "$downloaded_file" "$SCRIPT_PATH"
}

self_update_if_needed() {
  local update_url fetched_url temp_file remote_version

  if ! command -v curl >/dev/null 2>&1; then
    echo "Update check skipped: curl is not installed."
    return 0
  fi

  update_url="$(resolve_update_url)"
  if [ -z "$update_url" ]; then
    echo "Update check skipped: unable to resolve GitHub update URL."
    echo "Set CMP_VIDEO_UPDATE_URL to your raw script URL to enable updates."
    return 0
  fi

  temp_file="$(mktemp "${TMPDIR:-/tmp}/cmp_video_v2_update.XXXXXX")"
  fetched_url="${update_url}"
  if [[ "$fetched_url" == *\?* ]]; then
    fetched_url="${fetched_url}&ts=$(date +%s)"
  else
    fetched_url="${fetched_url}?ts=$(date +%s)"
  fi

  if ! curl -fsSL -H 'Cache-Control: no-cache' -H 'Pragma: no-cache' "$fetched_url" -o "$temp_file"; then
    rm -f "$temp_file"
    echo "Update check failed: could not download latest script from GitHub."
    return 0
  fi

  remote_version="$(extract_version_from_file "$temp_file")"
  if [ -z "$remote_version" ]; then
    rm -f "$temp_file"
    echo "Update check failed: downloaded script has no readable SCRIPT_VERSION."
    return 0
  fi

  if [ "$(is_newer_version "$remote_version" "$SCRIPT_VERSION")" = "1" ]; then
    echo "Updating ${SCRIPT_NAME} from ${SCRIPT_VERSION} to ${remote_version}"
    if install_updated_script "$temp_file"; then
      rm -f "$temp_file"
      return 10
    else
      rm -f "$temp_file"
      echo "Update install failed; keeping current script."
      return 0
    fi
  fi

  rm -f "$temp_file"
  echo "Already up to date (${SCRIPT_VERSION})."
  return 0
}

print_help() {
  cat <<EOF
cmp_video_v2.sh - Proxy/original-quality video encoder with optional SMPTE overlay

Usage:
  $0 <file>
  $0 --all
  $0 --recursive
  $0 --interactive [file]
  $0 --interactive [file]         # optionally save/update personal defaults
  $0 [--fhd] [--smpte] [--no-proxy-append] [--preserve-container] [--yes] [--delete-original] <file|--all|--recursive>
  $0 --original-quality [--smpte] [--preserve-container] [--yes] [--delete-original] <file|--all|--recursive>
  $0 --self-update

Examples:
  $0 clip.mov
  $0 --interactive
  $0 --fhd clip.mov
  $0 --smpte --all
  $0 --recursive
  $0 --original-quality --smpte interview.mkv
  $0 --delete-original --yes --all
  $0 --self-update

Options:
  --all                  Process all .mkv .mp4 .mov .m4v files in current directory
  --recursive, -r        Process supported files below the current directory
                         and write all outputs to the root ./cmp directory
  --interactive          Prompt for input and compatible settings in a guided menu
  --fhd                  Target 1080p proxy mode (default proxy mode is 720p)
  --original-quality     Re-encode at source resolution with high quality settings
  --smpte                Burn subtle SMPTE timecode overlay
  --no-proxy-append      Output name: cmp/<base>.<ext> instead of proxy suffix
  --npa                  Alias for --no-proxy-append
  --preserve-container   Keep source container extension instead of forcing .mp4
  --delete-original, --delete-originals
                         Delete source only after successful, non-empty output;
                         output is written beside the source instead of in ./cmp
  --yes, --force         Skip confirmation prompt after preflight overview
  --self-update, --update Check GitHub and install latest script version, then exit
  --no-update, --skip-update
                         Skip automatic startup update check
  -h, --help             Show this help menu

Output:
  Files are normally written to ./cmp
  With --delete-original(s), each output is written beside its source
  Recursive searches ignore all directories named cmp
  Existing output files are skipped

Interrupted Delete-Original Jobs:
  Recursive delete-original jobs keep a hidden .cmp_video_v2_resume queue
  Re-run with the same command and settings to resume only unfinished originals
  Encodes use hidden temporary files and publish outputs only after FFmpeg succeeds
  Same-name --no-proxy-append replacements are tracked by original file identity
  The resume queue is removed automatically when the job completes

Saved Settings:
  Personal defaults are loaded from ${SETTINGS_FILE}
  When your current settings differ, the script can prompt to update them

Update Source Priority:
  1) CMP_VIDEO_UPDATE_URL environment variable
  2) DEFAULT_UPDATE_URL in this script
  3) Git remote-derived raw GitHub URL
EOF
}

prompt_menu_choice() {
  local prompt="$1"
  local default_choice="$2"
  shift 2

  local options=("$@")
  local reply

  while true; do
    echo "$prompt" >&2
    local i=1
    for option in "${options[@]}"; do
      if [ "$i" -eq "$default_choice" ]; then
        printf "  %d) %s [default]\n" "$i" "$option" >&2
      else
        printf "  %d) %s\n" "$i" "$option" >&2
      fi
      i=$((i + 1))
    done

    printf "Choose [%s]: " "$default_choice" >&2
    if ! read -r reply; then
      echo >&2
      echo "Cancelled." >&2
      exit 0
    fi

    if [ -z "$reply" ]; then
      reply="$default_choice"
    fi

    if awk -v value="$reply" -v max="${#options[@]}" 'BEGIN { exit !(value ~ /^[0-9]+$/ && value >= 1 && value <= max) }'; then
      echo "$reply"
      return
    fi

    echo "Invalid selection. Enter a number from 1 to ${#options[@]}." >&2
    echo >&2
  done
}

prompt_yes_no() {
  local prompt="$1"
  local default_value="${2:-0}"
  local reply
  local default_hint="y/N"

  if [ "$default_value" -eq 1 ]; then
    default_hint="Y/n"
  fi

  while true; do
    printf "%s [%s] " "$prompt" "$default_hint" >&2
    if ! read -r reply; then
      echo >&2
      echo "Cancelled." >&2
      exit 0
    fi

    if [ -z "$reply" ]; then
      echo "$default_value"
      return
    fi

    case "$reply" in
      [Yy]|[Yy][Ee][Ss])
        echo "1"
        return
        ;;
      [Nn]|[Nn][Oo])
        echo "0"
        return
        ;;
    esac

    echo "Please answer y or n." >&2
  done
}

current_settings_match_saved() {
  [ "$HEIGHT" -eq "$SAVED_HEIGHT" ] && \
    [ "$ENABLE_SMPTE" -eq "$SAVED_ENABLE_SMPTE" ] && \
    [ "$ORIGINAL_QUALITY" -eq "$SAVED_ORIGINAL_QUALITY" ] && \
    [ "$NO_PROXY_APPEND" -eq "$SAVED_NO_PROXY_APPEND" ] && \
    [ "$PRESERVE_CONTAINER" -eq "$SAVED_PRESERVE_CONTAINER" ] && \
    [ "$AUTO_CONFIRM" -eq "$SAVED_AUTO_CONFIRM" ] && \
    [ "$DELETE_ORIGINAL" -eq "$SAVED_DELETE_ORIGINAL" ]
}

save_current_settings() {
  mkdir -p "$CONFIG_DIR"

  cat > "$SETTINGS_FILE" <<EOF
# Personal defaults for ${SCRIPT_NAME}
HEIGHT=${HEIGHT}
ENABLE_SMPTE=${ENABLE_SMPTE}
ORIGINAL_QUALITY=${ORIGINAL_QUALITY}
NO_PROXY_APPEND=${NO_PROXY_APPEND}
PRESERVE_CONTAINER=${PRESERVE_CONTAINER}
AUTO_CONFIRM=${AUTO_CONFIRM}
DELETE_ORIGINAL=${DELETE_ORIGINAL}
EOF

  SAVED_SETTINGS_LOADED=1
  SAVED_HEIGHT="$HEIGHT"
  SAVED_ENABLE_SMPTE="$ENABLE_SMPTE"
  SAVED_ORIGINAL_QUALITY="$ORIGINAL_QUALITY"
  SAVED_NO_PROXY_APPEND="$NO_PROXY_APPEND"
  SAVED_PRESERVE_CONTAINER="$PRESERVE_CONTAINER"
  SAVED_AUTO_CONFIRM="$AUTO_CONFIRM"
  SAVED_DELETE_ORIGINAL="$DELETE_ORIGINAL"
}

maybe_offer_save_settings() {
  local prompt default_value

  if [ ! -t 0 ] || [ ! -t 1 ]; then
    return
  fi

  if current_settings_match_saved; then
    return
  fi

  if [ "$SAVED_SETTINGS_LOADED" -eq 1 ]; then
    prompt="These settings differ from your saved defaults. Update saved settings?"
    default_value=0
  else
    prompt="Save these settings as your personal defaults?"
    default_value=1
  fi

  if [ "$(prompt_yes_no "$prompt" "$default_value")" -eq 1 ]; then
    save_current_settings
    echo "Saved personal settings to $SETTINGS_FILE"
  fi
}

prompt_input_file() {
  local default_value="$1"
  local reply

  while true; do
    if [ -n "$default_value" ]; then
      printf "Input file [%s]: " "$default_value" >&2
    else
      printf "Input file: " >&2
    fi

    if ! read -r reply; then
      echo >&2
      echo "Cancelled." >&2
      exit 0
    fi

    if [ -z "$reply" ]; then
      reply="$default_value"
    fi

    if [ -n "$reply" ]; then
      echo "$reply"
      return
    fi

    echo "Enter a file path or press Ctrl+C to cancel." >&2
  done
}

run_interactive_setup() {
  local selection

  if [ ! -t 0 ] || [ ! -t 1 ]; then
    echo "Error: --interactive requires a terminal."
    exit 1
  fi

  echo
  echo "Interactive setup"
  echo "-----------------"

  if [ "$INPUT" = "--all" ]; then
    selection=2
  elif [ -n "$INPUT" ]; then
    selection=1
  else
    selection=1
  fi

  if [ "$RECURSIVE" -eq 1 ]; then
    selection=3
  fi

  selection="$(prompt_menu_choice "Choose input source:" "$selection" "Single file" "All supported files in current directory" "All supported files recursively")"
  if [ "$selection" -eq 1 ]; then
    INPUT="$(prompt_input_file "$INPUT")"
    RECURSIVE=0
  elif [ "$selection" -eq 2 ]; then
    INPUT="--all"
    RECURSIVE=0
  else
    INPUT="--all"
    RECURSIVE=1
  fi
  echo

  if [ "$ORIGINAL_QUALITY" -eq 1 ]; then
    selection=3
  elif [ "$HEIGHT" -eq 1080 ]; then
    selection=2
  else
    selection=1
  fi

  selection="$(prompt_menu_choice "Choose encode mode:" "$selection" "720p proxy" "1080p proxy" "Original-quality re-encode")"
  case "$selection" in
    1)
      ORIGINAL_QUALITY=0
      HEIGHT=720
      ;;
    2)
      ORIGINAL_QUALITY=0
      HEIGHT=1080
      ;;
    3)
      ORIGINAL_QUALITY=1
      ;;
  esac

  ENABLE_SMPTE="$(prompt_yes_no "Burn SMPTE overlay?" "$ENABLE_SMPTE")"
  PRESERVE_CONTAINER="$(prompt_yes_no "Preserve source container extension?" "$PRESERVE_CONTAINER")"

  if [ "$ORIGINAL_QUALITY" -eq 1 ]; then
    NO_PROXY_APPEND=0
    echo
    echo "Output naming is fixed to original-quality suffixes in original-quality mode."
  else
    echo
    selection=1
    if [ "$NO_PROXY_APPEND" -eq 1 ]; then
      selection=2
    fi
    selection="$(prompt_menu_choice "Choose output naming:" "$selection" "Add proxy suffix" "Keep base name without proxy suffix")"
    if [ "$selection" -eq 2 ]; then
      NO_PROXY_APPEND=1
    else
      NO_PROXY_APPEND=0
    fi
  fi

  DELETE_ORIGINAL="$(prompt_yes_no "Delete originals after successful encode?" "$DELETE_ORIGINAL")"
  AUTO_CONFIRM="$(prompt_yes_no "Skip the final confirmation prompt?" "$AUTO_CONFIRM")"
}

get_video_fps() {
  local input="$1"
  local fps_raw
  fps_raw="$(ffprobe -v error -select_streams v:0 -show_entries stream=r_frame_rate -of default=nw=1:nk=1 "$input" 2>/dev/null | head -n 1 || true)"

  if [ -z "$fps_raw" ]; then
    echo "24"
    return
  fi

  if [[ "$fps_raw" == */* ]]; then
    awk -F'/' '{ if ($2 == 0) print "24"; else printf "%.6f", $1 / $2 }' <<< "$fps_raw"
  elif awk -v value="$fps_raw" 'BEGIN { exit !(value ~ /^[0-9]+([.][0-9]+)?$/) }'; then
    echo "$fps_raw"
  else
    echo "24"
  fi
}

get_duration_seconds() {
  local input="$1"
  ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$input" 2>/dev/null | head -n 1 || true
}

get_video_dimensions() {
  local input="$1"
  ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=p=0:s=x "$input" 2>/dev/null | head -n 1 || true
}

get_file_size_bytes() {
  local input="$1"
  wc -c < "$input" 2>/dev/null | tr -d '[:space:]' || true
}

format_bytes() {
  local bytes="${1:-}"

  if [ -z "$bytes" ]; then
    echo "unknown"
    return
  fi

  awk -v bytes="$bytes" '
    BEGIN {
      split("B KB MB GB TB", units, " ")
      value = bytes + 0
      unit = 1
      while (value >= 1024 && unit < 5) {
        value /= 1024
        unit++
      }
      if (unit == 1) {
        printf "%.0f %s", value, units[unit]
      } else {
        printf "%.1f %s", value, units[unit]
      }
    }
  '
}

format_duration() {
  local seconds="${1:-}"

  if [ -z "$seconds" ] || ! awk -v value="$seconds" 'BEGIN { exit !(value ~ /^[0-9]+([.][0-9]+)?$/) }'; then
    echo "unknown"
    return
  fi

  awk -v value="$seconds" '
    BEGIN {
      total = int(value + 0.5)
      hours = int(total / 3600)
      minutes = int((total % 3600) / 60)
      secs = total % 60
      printf "%02d:%02d:%02d", hours, minutes, secs
    }
  '
}

format_eta() {
  local seconds="${1:-}"

  if [ -z "$seconds" ] || ! awk -v value="$seconds" 'BEGIN { exit !(value ~ /^[0-9]+([.][0-9]+)?$/ && value >= 0) }'; then
    echo "--:--:--"
    return
  fi

  awk -v value="$seconds" '
    BEGIN {
      total = int(value + 0.5)
      hours = int(total / 3600)
      minutes = int((total % 3600) / 60)
      secs = total % 60
      printf "%02d:%02d:%02d", hours, minutes, secs
    }
  '
}

progress_time_to_seconds() {
  local timestamp="${1:-}"

  awk -F: -v value="$timestamp" '
    BEGIN {
      part_count = split(value, parts, ":")
      if (part_count != 3) {
        print "0"
        exit
      }
      printf "%.6f", (parts[1] * 3600) + (parts[2] * 60) + parts[3]
    }
  '
}

render_encode_progress() {
  local file_index="$1"
  local file_total="$2"
  local file_duration="$3"
  local completed_duration="$4"
  local job_duration="$5"
  local file_started="$6"
  local job_started="$7"
  local display_name="$8"
  local line key value progress_state
  local out_seconds=0
  local file_percent=0
  local job_percent=0
  local file_eta=""
  local job_eta=""
  local now file_elapsed job_elapsed
  local last_bucket=-1
  local current_bucket
  local terminal_output=0

  if [ -t 1 ]; then
    terminal_output=1
  fi

  printf "[%d/%d] %s\n" "$file_index" "$file_total" "$display_name"

  while IFS= read -r line; do
    key="${line%%=*}"
    value="${line#*=}"

    case "$key" in
      out_time)
        out_seconds="$(progress_time_to_seconds "$value")"
        ;;
      progress)
        progress_state="$value"
        now="$(date +%s)"
        file_elapsed=$((now - file_started))
        job_elapsed=$((now - job_started))

        if [ "$progress_state" = "end" ]; then
          file_percent=100
          out_seconds="$file_duration"
        elif awk -v duration="$file_duration" 'BEGIN { exit !((duration + 0) > 0) }'; then
          file_percent="$(awk -v current="$out_seconds" -v duration="$file_duration" '
            BEGIN {
              percent = current * 100 / duration
              if (percent < 0) percent = 0
              if (percent > 99.9) percent = 99.9
              printf "%.1f", percent
            }
          ')"
        else
          file_percent=0
        fi

        if awk -v percent="$file_percent" 'BEGIN { exit !((percent + 0) > 0) }'; then
          file_eta="$(awk -v elapsed="$file_elapsed" -v percent="$file_percent" '
            BEGIN { printf "%.0f", elapsed * (100 - percent) / percent }
          ')"
        else
          file_eta=""
        fi

        if awk -v duration="$job_duration" 'BEGIN { exit !((duration + 0) > 0) }'; then
          job_percent="$(awk \
            -v completed="$completed_duration" \
            -v current="$out_seconds" \
            -v duration="$job_duration" '
            BEGIN {
              percent = (completed + current) * 100 / duration
              if (percent < 0) percent = 0
              if (percent > 100) percent = 100
              printf "%.1f", percent
            }
          ')"
        else
          job_percent="$(awk \
            -v index="$file_index" \
            -v total="$file_total" \
            -v percent="$file_percent" '
            BEGIN { printf "%.1f", (((index - 1) + (percent / 100)) * 100) / total }
          ')"
        fi

        if awk -v percent="$job_percent" 'BEGIN { exit !((percent + 0) > 0) }'; then
          job_eta="$(awk -v elapsed="$job_elapsed" -v percent="$job_percent" '
            BEGIN { printf "%.0f", elapsed * (100 - percent) / percent }
          ')"
        else
          job_eta=""
        fi

        current_bucket="$(awk -v percent="$file_percent" 'BEGIN { print int(percent / 10) }')"
        if [ "$terminal_output" -eq 1 ]; then
          printf "\r\033[K  File %5.1f%%  ETA %s  |  Job %5.1f%%  ETA %s" \
            "$file_percent" "$(format_eta "$file_eta")" \
            "$job_percent" "$(format_eta "$job_eta")"
        elif [ "$current_bucket" -gt "$last_bucket" ] || [ "$progress_state" = "end" ]; then
          printf "  File %5.1f%%  ETA %s  |  Job %5.1f%%  ETA %s\n" \
            "$file_percent" "$(format_eta "$file_eta")" \
            "$job_percent" "$(format_eta "$job_eta")"
          last_bucket="$current_bucket"
        fi

        if [ "$progress_state" = "end" ]; then
          if [ "$terminal_output" -eq 1 ]; then
            printf "\n"
          fi
          return
        fi
        ;;
    esac
  done

  if [ "$terminal_output" -eq 1 ]; then
    printf "\n"
  fi
}

yes_no() {
  if [ "${1:-0}" -eq 1 ]; then
    echo "yes"
  else
    echo "no"
  fi
}

describe_mode() {
  if [ "$ORIGINAL_QUALITY" -eq 1 ]; then
    echo "Original-quality re-encode"
  else
    echo "${HEIGHT}p proxy"
  fi
}

describe_video_settings() {
  if [ "$ORIGINAL_QUALITY" -eq 1 ]; then
    echo "libx264 CRF 14, preset slow, source resolution"
  else
    echo "libx264 CRF 20, preset medium, scale to ${HEIGHT}p"
  fi
}

describe_output_container() {
  if [ "$PRESERVE_CONTAINER" -eq 1 ]; then
    echo "preserve source extension"
  else
    echo "mp4"
  fi
}

describe_output_naming() {
  if [ "$ORIGINAL_QUALITY" -eq 1 ]; then
    if [ "$ENABLE_SMPTE" -eq 1 ]; then
      echo "<base>_smpte_oq<ext>"
    else
      echo "<base>_oq<ext>"
    fi
  elif [ "$NO_PROXY_APPEND" -eq 1 ]; then
    echo "<base><ext>"
  elif [ "$HEIGHT" -eq 1080 ]; then
    echo "<base>_proxy_fhd<ext>"
  else
    echo "<base>_proxy<ext>"
  fi
}

get_output_file() {
  local input_file="$1"
  local filename base input_ext output_ext output_dir

  filename="$(basename "$input_file")"
  output_dir="cmp"
  if [ "$DELETE_ORIGINAL" -eq 1 ]; then
    output_dir="$(dirname "$input_file")"
  fi

  base="${filename%.*}"
  if [ "$base" = "$filename" ]; then
    input_ext=""
  else
    input_ext=".${filename##*.}"
  fi

  output_ext=".mp4"
  if [ "$PRESERVE_CONTAINER" -eq 1 ] && [ -n "$input_ext" ]; then
    output_ext="$input_ext"
  fi

  if [ "$ORIGINAL_QUALITY" -eq 1 ]; then
    if [ "$ENABLE_SMPTE" -eq 1 ]; then
      echo "${output_dir}/${base}_smpte_oq${output_ext}"
    else
      echo "${output_dir}/${base}_oq${output_ext}"
    fi
  elif [ "$NO_PROXY_APPEND" -eq 1 ]; then
    echo "${output_dir}/${base}${output_ext}"
  elif [ "$HEIGHT" -eq 1080 ]; then
    echo "${output_dir}/${base}_proxy_fhd${output_ext}"
  else
    echo "${output_dir}/${base}_proxy${output_ext}"
  fi
}

resume_settings_signature() {
  printf 'HEIGHT=%s;SMPTE=%s;OQ=%s;NPA=%s;CONTAINER=%s;DELETE=%s\n' \
    "$HEIGHT" "$ENABLE_SMPTE" "$ORIGINAL_QUALITY" "$NO_PROXY_APPEND" \
    "$PRESERVE_CONTAINER" "$DELETE_ORIGINAL"
}

get_file_identity() {
  local input_file="$1"
  local identity

  identity="$(stat -f '%d:%i:%z:%m' "$input_file" 2>/dev/null || true)"
  if [ -n "$identity" ]; then
    echo "$identity"
    return
  fi

  stat -c '%d:%i:%s:%Y' "$input_file" 2>/dev/null || true
}

write_resume_manifest() {
  local temp_file="$1"
  local i

  printf '%s\0' "CMP_VIDEO_V2_RESUME_V2" > "$temp_file"
  printf '%s\0' "$(resume_settings_signature)" >> "$temp_file"
  for ((i = 0; i < ${#RESUME_PATHS[@]}; i++)); do
    printf '%s\0' "${RESUME_IDENTITIES[$i]}" >> "$temp_file"
    printf '%s\0' "${RESUME_PATHS[$i]}" >> "$temp_file"
  done
}

save_resume_queue() {
  local temp_file

  temp_file="$(mktemp "${RESUME_FILE}.tmp.XXXXXX")"
  write_resume_manifest "$temp_file"
  mv -f -- "$temp_file" "$RESUME_FILE"
}

load_resume_queue() {
  local record_number=0
  local record expected_signature
  local pending_identity=""
  local current_identity

  expected_signature="$(resume_settings_signature)"
  RESUME_PATHS=()
  RESUME_IDENTITIES=()

  while IFS= read -r -d '' record; do
    record_number=$((record_number + 1))
    if [ "$record_number" -eq 1 ]; then
      if [ "$record" != "CMP_VIDEO_V2_RESUME_V2" ]; then
        echo "Error: unreadable resume file: $RESUME_FILE" >&2
        exit 1
      fi
    elif [ "$record_number" -eq 2 ]; then
      if [ "$record" != "$expected_signature" ]; then
        echo "Error: this interrupted job used different encoding settings." >&2
        echo "Re-run with the original settings to resume it." >&2
        echo "Resume file: $RESUME_FILE" >&2
        exit 1
      fi
    elif [ $((record_number % 2)) -eq 1 ]; then
      pending_identity="$record"
    elif [ -f "$record" ]; then
      current_identity="$(get_file_identity "$record")"
      if [ "$NO_PROXY_APPEND" -eq 1 ] && \
         [ -n "$pending_identity" ] && \
         [ "$current_identity" != "$pending_identity" ]; then
        echo "Recovered completed same-name output: $record"
      else
        RESUME_IDENTITIES+=( "$pending_identity" )
        RESUME_PATHS+=( "$record" )
      fi
    fi
  done < "$RESUME_FILE"

  if [ "$record_number" -lt 2 ] || [ $((record_number % 2)) -ne 0 ]; then
    echo "Error: incomplete resume file: $RESUME_FILE" >&2
    exit 1
  fi

  INPUT_FILES=( ${RESUME_PATHS[@]+"${RESUME_PATHS[@]}"} )
  RESUME_LOADED=1

  if [ "${#INPUT_FILES[@]}" -eq 0 ]; then
    rm -f -- "$RESUME_FILE"
  else
    save_resume_queue
  fi
}

remove_from_resume_queue() {
  local completed_file="$1"
  local i
  local remaining_paths=()
  local remaining_identities=()

  if [ ! -f "$RESUME_FILE" ]; then
    return
  fi

  for ((i = 0; i < ${#RESUME_PATHS[@]}; i++)); do
    if [ "${RESUME_PATHS[$i]}" != "$completed_file" ]; then
      remaining_paths+=( "${RESUME_PATHS[$i]}" )
      remaining_identities+=( "${RESUME_IDENTITIES[$i]}" )
    fi
  done

  RESUME_PATHS=( ${remaining_paths[@]+"${remaining_paths[@]}"} )
  RESUME_IDENTITIES=( ${remaining_identities[@]+"${remaining_identities[@]}"} )

  if [ "${#RESUME_PATHS[@]}" -eq 0 ]; then
    rm -f -- "$RESUME_FILE"
  else
    save_resume_queue
  fi
}

paths_are_same_file() {
  local first_path="$1"
  local second_path="$2"

  [ -e "$first_path" ] && [ -e "$second_path" ] && [ "$first_path" -ef "$second_path" ]
}

pick_audio_stream() {
  local input="$1"

  local rows
  rows="$(ffprobe -v error -select_streams a \
    -show_entries stream=index,channels:stream_tags=language \
    -of csv=p=0 "$input" 2>/dev/null || true)"

  if [ -z "$rows" ]; then
    echo "1 2"
    return
  fi

  local chosen
  chosen="$(echo "$rows" | awk -F',' 'tolower($3)=="eng" {print; exit}')"
  if [ -z "$chosen" ]; then
    chosen="$(echo "$rows" | awk -F',' 'tolower($3)=="en" {print; exit}')"
  fi
  if [ -z "$chosen" ]; then
    chosen="$(echo "$rows" | head -n 1)"
  fi

  echo "$chosen" | awk -F',' '{print $1, $2}'
}

estimate_output_size_bytes() {
  local input_file="$1"
  local duration source_size dims source_w source_h fps target_width
  local estimate_bytes

  duration="$(get_duration_seconds "$input_file")"
  if ! awk -v value="$duration" 'BEGIN { exit !((value + 0) > 0) }'; then
    echo ""
    return
  fi

  source_size="$(get_file_size_bytes "$input_file")"
  if [ "$ORIGINAL_QUALITY" -eq 1 ]; then
    echo "$source_size"
    return
  fi

  dims="$(get_video_dimensions "$input_file")"
  if [[ "$dims" == *x* ]]; then
    source_w="${dims%x*}"
    source_h="${dims#*x}"
  else
    source_w=$((HEIGHT * 16 / 9))
    source_h="$HEIGHT"
  fi

  fps="$(get_video_fps "$input_file")"
  target_width="$(awk -v sw="$source_w" -v sh="$source_h" -v th="$HEIGHT" '
    BEGIN {
      if ((sh + 0) <= 0) {
        width = th * 16 / 9
      } else {
        width = sw * th / sh
      }
      width = int((width + 1) / 2) * 2
      if (width < 2) {
        width = 2
      }
      printf "%.0f", width
    }
  ')"

  estimate_bytes="$(awk -v tw="$target_width" -v th="$HEIGHT" -v fps="$fps" -v duration="$duration" '
    BEGIN {
      bpp = 0.075
      video_kbps = tw * th * fps * bpp / 1000
      if (th <= 720) {
        if (video_kbps < 1200) video_kbps = 1200
        if (video_kbps > 4500) video_kbps = 4500
      } else {
        if (video_kbps < 2500) video_kbps = 2500
        if (video_kbps > 9500) video_kbps = 9500
      }
      total_kbps = video_kbps + 128
      printf "%.0f", duration * total_kbps * 1000 / 8
    }
  ')"

  echo "$estimate_bytes"
}

collect_input_files() {
  local input_file

  INPUT_FILES=()

  if [ "$RECURSIVE" -eq 1 ] && [ "$DELETE_ORIGINAL" -eq 1 ] && [ -f "$RESUME_FILE" ]; then
    echo "Resuming interrupted delete-original job from $RESUME_FILE"
    load_resume_queue
    return
  fi

  if [ "$INPUT" = "--all" ] && [ "$RECURSIVE" -eq 1 ]; then
    while IFS= read -r -d '' input_file; do
      INPUT_FILES+=( "$input_file" )
    done < <(
      find . \
        -type d -name cmp -prune -o \
        -type f \( -iname '*.mkv' -o -iname '*.mp4' -o -iname '*.mov' -o -iname '*.m4v' \) \
        ! -name '.*.cmp_video_tmp.*' \
        -print0
    )
  elif [ "$INPUT" = "--all" ]; then
    shopt -s nullglob
    INPUT_FILES=( *.mkv *.mp4 *.mov *.m4v )
    shopt -u nullglob
  elif [ -n "$INPUT" ]; then
    INPUT_FILES=( "$INPUT" )
  fi
}

validate_input_files() {
  local input_file
  local missing=0

  for input_file in "${INPUT_FILES[@]}"; do
    if [ ! -f "$input_file" ]; then
      echo "File not found: $input_file"
      missing=1
    fi
  done

  if [ "$missing" -eq 1 ]; then
    exit 1
  fi
}

print_preflight_summary() {
  local input_file output_file source_bytes duration estimate_bytes output_bytes
  local total_source_bytes=0
  local total_estimated_bytes=0
  local total_duration_seconds=0
  local rounded_duration
  local status

  PREFLIGHT_PROCESS_COUNT=0
  PREFLIGHT_SKIP_COUNT=0

  echo
  echo "Overview"
  echo "--------"
  echo "Mode: $(describe_mode)"
  echo "Video: $(describe_video_settings)"
  echo "Audio: AAC 128k stereo"
  echo "SMPTE overlay: $(yes_no "$ENABLE_SMPTE")"
  echo "Preserve container: $(yes_no "$PRESERVE_CONTAINER")"
  echo "Delete originals: $(yes_no "$DELETE_ORIGINAL")"
  echo "Output container: $(describe_output_container)"
  echo "Output naming: $(describe_output_naming)"
  echo "Recursive search: $(yes_no "$RECURSIVE")"
  echo "Matched files: ${#INPUT_FILES[@]}"
  echo

  for input_file in "${INPUT_FILES[@]}"; do
    output_file="$(get_output_file "$input_file")"
    source_bytes="$(get_file_size_bytes "$input_file")"
    duration="$(get_duration_seconds "$input_file")"
    estimate_bytes="$(estimate_output_size_bytes "$input_file")"
    status="CREATE"

    if [ -f "$output_file" ] && ! paths_are_same_file "$input_file" "$output_file"; then
      output_bytes="$(get_file_size_bytes "$output_file")"
      if [ "$RESUME_LOADED" -eq 1 ] && [ -s "$output_file" ]; then
        status="FINALIZE"
        PREFLIGHT_PROCESS_COUNT=$((PREFLIGHT_PROCESS_COUNT + 1))
      else
        status="SKIP"
        PREFLIGHT_SKIP_COUNT=$((PREFLIGHT_SKIP_COUNT + 1))
      fi
    else
      PREFLIGHT_PROCESS_COUNT=$((PREFLIGHT_PROCESS_COUNT + 1))
      output_bytes=""
    fi

    if [ -n "$source_bytes" ]; then
      total_source_bytes=$((total_source_bytes + source_bytes))
    fi

    if awk -v value="$duration" 'BEGIN { exit !((value + 0) > 0) }'; then
      rounded_duration="$(awk -v value="$duration" 'BEGIN { printf "%.0f", value }')"
      total_duration_seconds=$((total_duration_seconds + rounded_duration))
    fi

    if [ "$status" = "CREATE" ] && [ -n "$estimate_bytes" ]; then
      total_estimated_bytes=$((total_estimated_bytes + estimate_bytes))
    fi

    echo "[$status] $input_file"
    echo "  source: $(format_bytes "$source_bytes") | duration: $(format_duration "$duration")"
    echo "  output: $output_file"

    if [ "$status" = "FINALIZE" ] && [ -n "$output_bytes" ]; then
      echo "  output size: $(format_bytes "$output_bytes") (encode complete; original deletion pending)"
    elif [ "$status" = "SKIP" ] && [ -n "$output_bytes" ]; then
      echo "  output size: $(format_bytes "$output_bytes") (existing)"
    elif [ -n "$estimate_bytes" ]; then
      echo "  estimated output: $(format_bytes "$estimate_bytes")"
    else
      echo "  estimated output: unknown"
    fi
  done

  echo
  echo "Summary"
  echo "-------"
  echo "To process: $PREFLIGHT_PROCESS_COUNT file(s)"
  echo "Skipping existing outputs: $PREFLIGHT_SKIP_COUNT file(s)"
  echo "Total input duration: $(format_duration "$total_duration_seconds")"
  echo "Total source size: $(format_bytes "$total_source_bytes")"

  if [ "$PREFLIGHT_PROCESS_COUNT" -gt 0 ]; then
    echo "Estimated new output size: $(format_bytes "$total_estimated_bytes")"
  fi

  if [ "$ORIGINAL_QUALITY" -eq 1 ]; then
    echo "Estimate note: original-quality size estimates are based on source file sizes and may vary with content."
  else
    echo "Estimate note: proxy size estimates are rough and based on duration, frame rate, target resolution, and 128k AAC audio."
  fi

  if [ "$DELETE_ORIGINAL" -eq 1 ]; then
    echo "Delete note: originals are removed only after a successful encode creates a non-empty output file."
  fi

  echo
}

confirm_preflight() {
  local reply

  print_preflight_summary

  if [ "$PREFLIGHT_PROCESS_COUNT" -eq 0 ]; then
    echo "Nothing to process."
    exit 0
  fi

  if [ "$AUTO_CONFIRM" -eq 1 ]; then
    echo "Auto-confirm enabled; starting processing."
    return
  fi

  if [ ! -t 0 ]; then
    echo "Interactive confirmation is required. Re-run with --yes to skip the prompt."
    exit 1
  fi

  if [ "$DELETE_ORIGINAL" -eq 1 ]; then
    printf "Proceed with processing and delete originals after successful outputs? [y/N] "
  else
    printf "Proceed with processing? [y/N] "
  fi
  if ! read -r reply; then
    echo
    echo "Cancelled."
    exit 0
  fi

  case "$reply" in
    [Yy]|[Yy][Ee][Ss])
      ;;
    *)
      echo "Cancelled."
      exit 0
      ;;
  esac
}

compress_file() {
  local input_file="$1"
  local file_index="$2"
  local file_total="$3"
  local file_duration="$4"
  local completed_duration="$5"
  local job_duration="$6"
  local job_started="$7"

  if [ ! -f "$input_file" ]; then
    echo "File not found: $input_file"
    return 1
  fi

  local output_file encode_output replace_in_place=0
  output_file="$(get_output_file "$input_file")"
  encode_output="$output_file"

  if [ "$RESUME_LOADED" -eq 1 ] && [ -s "$output_file" ] && ! paths_are_same_file "$input_file" "$output_file"; then
    printf "[%d/%d] %s\n" "$file_index" "$file_total" "$(basename "$input_file")"
    rm -- "$input_file"
    echo "  Encode was already complete; deleted original and finalized: $output_file"
    return 0
  fi

  if paths_are_same_file "$input_file" "$output_file"; then
    replace_in_place=1
  fi

  if [ "$DELETE_ORIGINAL" -eq 1 ] || [ "$replace_in_place" -eq 1 ]; then
    local output_filename output_base output_ext
    output_filename="$(basename "$output_file")"
    output_base="${output_filename%.*}"
    output_ext=".${output_filename##*.}"
    encode_output="$(dirname "$output_file")/.${output_base}.cmp_video_tmp.$$${output_ext}"
  fi

  local a_stream ch
  read -r a_stream ch < <(pick_audio_stream "$input_file")

  local vf_filter
  if [ "$ORIGINAL_QUALITY" -eq 1 ]; then
    vf_filter=""
  else
    vf_filter="scale=-1:${HEIGHT}"
  fi

  if [ "$ENABLE_SMPTE" -eq 1 ]; then
    local fps drawtext_filter
    fps="$(get_video_fps "$input_file")"
    drawtext_filter="drawtext=timecode='00\\:00\\:00\\:00':timecode_rate=${fps}:fontsize=h/30:fontcolor=white@0.55:box=1:boxcolor=black@0.22:boxborderw=2:shadowx=1:shadowy=1:shadowcolor=black@0.7:x=w-tw-w*0.02:y=h-th-h*0.03"
    if [ -n "$vf_filter" ]; then
      vf_filter="${vf_filter},${drawtext_filter}"
    else
      vf_filter="$drawtext_filter"
    fi
    echo "  SMPTE overlay enabled (timecode_rate=${fps})"
  fi

  if [ "$ORIGINAL_QUALITY" -eq 1 ]; then
    echo "Creating original-quality encode (audio stream 0:${a_stream}): $input_file → $output_file"
  else
    echo "Creating ${HEIGHT}p proxy (${ch}ch, audio stream 0:${a_stream}): $input_file → $output_file"
  fi

  local audio_args=()
  local video_args=()
  local filter_args=()

  if [ "$ORIGINAL_QUALITY" -eq 1 ]; then
    # Keep video quality high and re-encode audio at high quality for compatibility.
    audio_args=( -c:a aac -b:a 192k )
    video_args=( -c:v libx264 -crf 14 -preset slow -fps_mode passthrough )
  else
    if [ "${ch:-2}" -ge 6 ]; then
      audio_args=(
        -filter:a "pan=stereo|FL=0.707*FL+0.707*FC+0.707*BL+0.707*SL+0.5*LFE|FR=0.707*FR+0.707*FC+0.707*BR+0.707*SR+0.5*LFE"
        -ac 2
      )
    else
      audio_args=( -ac 2 )
    fi
    audio_args+=( -c:a aac -b:a 128k )
    video_args=( -c:v libx264 -crf 20 -preset medium -pix_fmt yuv420p -fps_mode passthrough )
  fi

  if [ -n "$vf_filter" ]; then
    filter_args=( -vf "$vf_filter" )
  fi

  local error_log file_started
  local pipeline_status=()
  error_log="$(mktemp "${TMPDIR:-/tmp}/cmp_video_v2_ffmpeg.XXXXXX")"
  file_started="$(date +%s)"

  set +e
  ffmpeg -hide_banner -loglevel error -nostats -progress pipe:1 \
      -sn \
      -i "$input_file" \
      -map 0:v:0 -map "0:${a_stream}" \
      ${filter_args[@]+"${filter_args[@]}"} \
      "${video_args[@]}" \
      "${audio_args[@]}" \
      "$encode_output" 2>"$error_log" |
    render_encode_progress \
      "$file_index" "$file_total" "$file_duration" \
      "$completed_duration" "$job_duration" \
      "$file_started" "$job_started" "$(basename "$input_file")"
  pipeline_status=("${PIPESTATUS[@]}")
  set -e

  if [ "${pipeline_status[0]}" -ne 0 ]; then
    echo "FFmpeg failed while encoding: $input_file" >&2
    if [ -s "$error_log" ]; then
      sed 's/^/  /' "$error_log" >&2
    fi
    rm -f -- "$error_log"
    rm -f -- "$encode_output"
    return 1
  fi
  rm -f -- "$error_log"

  if [ "$DELETE_ORIGINAL" -eq 1 ]; then
    if [ ! -s "$encode_output" ]; then
      echo "Output file missing or empty after encode; original kept: $input_file"
      return 1
    fi

    if [ "$encode_output" != "$output_file" ]; then
      mv -f -- "$encode_output" "$output_file"
    fi

    if [ "$replace_in_place" -eq 1 ]; then
      echo "Replaced original with encoded output: $output_file"
    else
      rm -- "$input_file"
      echo "Deleted original: $input_file"
    fi
  fi
}

if [ "$SHOW_HELP" -eq 1 ] || [ "${#ORIGINAL_ARGS[@]}" -eq 0 ]; then
  print_help
  exit 0
fi

if [ "$SKIP_UPDATE" -eq 0 ]; then
  set +e
  self_update_if_needed
  update_exit_code=$?
  set -e

  if [ "$update_exit_code" -eq 10 ]; then
    if [ "$SELF_UPDATE_ONLY" -eq 1 ]; then
      echo "Update installed successfully."
      exit 0
    fi

    echo "Restarting with updated script..."
    exec "$SCRIPT_PATH" --skip-update "${ORIGINAL_ARGS[@]}"
  fi
fi

if [ "$SELF_UPDATE_ONLY" -eq 1 ]; then
  exit 0
fi

if [ "$INTERACTIVE_MODE" -eq 1 ]; then
  run_interactive_setup
fi

maybe_offer_save_settings

if [ "$DELETE_ORIGINAL" -eq 0 ]; then
  mkdir -p "cmp"
fi

if [ "$INPUT" != "--all" ] && [ -z "$INPUT" ]; then
  echo "Error: missing input file or --all."
  echo
  print_help
  exit 1
fi

collect_input_files

if [ "${#INPUT_FILES[@]}" -eq 0 ]; then
  echo "No matching video files found."
  exit 0
fi

validate_input_files
confirm_preflight

PROCESS_FILES=()
PROCESS_DURATIONS=()
JOB_TOTAL_DURATION=0

for file in "${INPUT_FILES[@]}"; do
  output_file="$(get_output_file "$file")"
  if [ -f "$output_file" ] && ! paths_are_same_file "$file" "$output_file"; then
    if [ "$RESUME_LOADED" -eq 0 ] || [ ! -s "$output_file" ]; then
      continue
    fi
  fi

  duration="$(get_duration_seconds "$file")"
  if ! awk -v value="$duration" 'BEGIN { exit !((value + 0) > 0) }'; then
    duration=0
  fi

  PROCESS_FILES+=( "$file" )
  PROCESS_DURATIONS+=( "$duration" )
  JOB_TOTAL_DURATION="$(awk -v total="$JOB_TOTAL_DURATION" -v duration="$duration" '
    BEGIN { printf "%.6f", total + duration }
  ')"
done

JOB_STARTED="$(date +%s)"
COMPLETED_DURATION=0
PROCESS_TOTAL="${#PROCESS_FILES[@]}"

if [ "$RECURSIVE" -eq 1 ] && [ "$DELETE_ORIGINAL" -eq 1 ] && [ "$RESUME_LOADED" -eq 0 ]; then
  RESUME_PATHS=( "${PROCESS_FILES[@]}" )
  RESUME_IDENTITIES=()
  for file in "${RESUME_PATHS[@]}"; do
    RESUME_IDENTITIES+=( "$(get_file_identity "$file")" )
  done
  save_resume_queue
fi

for ((i = 0; i < PROCESS_TOTAL; i++)); do
  compress_file \
    "${PROCESS_FILES[$i]}" "$((i + 1))" "$PROCESS_TOTAL" \
    "${PROCESS_DURATIONS[$i]}" "$COMPLETED_DURATION" \
    "$JOB_TOTAL_DURATION" "$JOB_STARTED"
  if [ "$RECURSIVE" -eq 1 ] && [ "$DELETE_ORIGINAL" -eq 1 ]; then
    remove_from_resume_queue "${PROCESS_FILES[$i]}"
  fi
  COMPLETED_DURATION="$(awk \
    -v completed="$COMPLETED_DURATION" \
    -v duration="${PROCESS_DURATIONS[$i]}" '
    BEGIN { printf "%.6f", completed + duration }
  ')"
done

echo "Completed ${PROCESS_TOTAL} file(s) in $(format_duration "$(( $(date +%s) - JOB_STARTED ))")."
