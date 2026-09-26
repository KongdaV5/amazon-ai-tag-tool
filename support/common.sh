#!/bin/bash
# Shared helpers for Amazon AI metadata Finder Quick Actions.

TOOL_TITLE='Amazon AI 标签工具'
TAG_VALUE='contains-synthetic-performer'
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
TOOL_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
RUNTIME_DIR="$TOOL_ROOT/runtime"
EXIFTOOL_PL="$RUNTIME_DIR/exiftool.pl"
ICON_PATH="$TOOL_ROOT/assets/Amazon_AI_Tag.icns"

show_alert() {
  local message="$1"
  local level="${2:-informational}"
  if [[ -x /usr/bin/osascript ]]; then
    /usr/bin/osascript - "$TOOL_TITLE" "$message" "$level" "$ICON_PATH" <<'APPLESCRIPT' >/dev/null 2>&1
on run argv
    set toolTitle to item 1 of argv
    set msg to item 2 of argv
    set alertLevel to item 3 of argv
    set iconPath to item 4 of argv

    tell application "System Events"
        activate
        try
            set iconFile to POSIX file iconPath as alias
            display dialog msg with title toolTitle buttons {"好"} default button "好" with icon iconFile
        on error
            if alertLevel is "critical" then
                display alert toolTitle message msg as critical buttons {"好"} default button "好"
            else if alertLevel is "warning" then
                display alert toolTitle message msg as warning buttons {"好"} default button "好"
            else
                display alert toolTitle message msg as informational buttons {"好"} default button "好"
            end if
        end try
    end tell
end run
APPLESCRIPT
  else
    printf '%s\n%s\n' "$TOOL_TITLE" "$message"
  fi
}

if [[ -x /usr/bin/perl && -f "$EXIFTOOL_PL" ]]; then
  EXIFTOOL_MODE='bundled'
elif command -v exiftool >/dev/null 2>&1; then
  EXIFTOOL_MODE='system'
else
  show_alert $'无法启动 ExifTool。\n\n请重新运行“安装 Finder 右键.command”。' critical
  exit 1
fi

run_exiftool() {
  if [[ "$EXIFTOOL_MODE" == 'system' ]]; then
    command exiftool "$@"
  else
    /usr/bin/perl "$EXIFTOOL_PL" "$@"
  fi
}

is_supported_image() {
  local path="$1"
  local ext="${path##*.}"
  ext="$(printf '%s' "$ext" | /usr/bin/tr '[:upper:]' '[:lower:]')"
  case "$ext" in
    jpg|jpeg|png|tif|tiff|webp) return 0 ;;
    *) return 1 ;;
  esac
}

subject_has_tag() {
  local subject="$1"
  case "|||$subject|||" in
    *"|||$TAG_VALUE|||"*) return 0 ;;
    *) return 1 ;;
  esac
}

reveal_path() {
  local path="$1"
  if [[ -x /usr/bin/open ]]; then
    /usr/bin/open -R "$path" >/dev/null 2>&1 || true
  fi
}
