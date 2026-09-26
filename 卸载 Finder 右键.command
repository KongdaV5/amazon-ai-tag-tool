#!/bin/bash
# Uninstall Finder Quick Actions and support files. Does not delete processed images.

set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
INSTALL_DIR="$HOME/Library/Application Support/AmazonAITagTool"
SERVICES_DIR="$HOME/Library/Services"
ICON_PATH="$SCRIPT_DIR/assets/Amazon_AI_Tag.icns"

rm -rf "$SERVICES_DIR/添加 Amazon AI 标签.workflow" "$SERVICES_DIR/检查 Amazon AI 标签.workflow" "$INSTALL_DIR"

if [[ -x /System/Library/CoreServices/pbs ]]; then
  /System/Library/CoreServices/pbs -flush >/dev/null 2>&1 || true
fi

if [[ -x /usr/bin/osascript ]]; then
  /usr/bin/osascript - "$ICON_PATH" <<'APPLESCRIPT' >/dev/null 2>&1
on run argv
  set iconPath to item 1 of argv
  tell application "System Events"
    activate
    try
      set iconFile to POSIX file iconPath as alias
      display dialog "Finder 右键快速操作已卸载。已处理图片不会被删除。" with title "Amazon AI 标签工具" buttons {"好"} default button "好" with icon iconFile
    on error
      display alert "Amazon AI 标签工具" message "Finder 右键快速操作已卸载。已处理图片不会被删除。" as informational buttons {"好"} default button "好"
    end try
  end tell
end run
APPLESCRIPT
else
  printf '%s\n' 'Finder 右键快速操作已卸载。'
fi
exit 0
