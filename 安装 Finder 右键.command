#!/bin/bash
# Install Finder Quick Actions for Amazon AI metadata tool.

set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
INSTALL_DIR="$HOME/Library/Application Support/AmazonAITagTool"
SERVICES_DIR="$HOME/Library/Services"
ADD_NAME='添加 Amazon AI 标签.workflow'
CHECK_NAME='检查 Amazon AI 标签.workflow'
ICON_PATH="$SCRIPT_DIR/assets/Amazon_AI_Tag.icns"

show_result() {
  local msg="$1"
  if [[ -x /usr/bin/osascript ]]; then
    /usr/bin/osascript - "$msg" "$ICON_PATH" <<'APPLESCRIPT' >/dev/null 2>&1
on run argv
  set msg to item 1 of argv
  set iconPath to item 2 of argv
  tell application "System Events"
    activate
    try
      set iconFile to POSIX file iconPath as alias
      display dialog msg with title "Amazon AI 标签工具" buttons {"好"} default button "好" with icon iconFile
    on error
      display alert "Amazon AI 标签工具" message msg as informational buttons {"好"} default button "好"
    end try
  end tell
end run
APPLESCRIPT
  else
    printf '%s\n' "$msg"
  fi
}

if [[ ! -d "$SCRIPT_DIR/runtime" || ! -d "$SCRIPT_DIR/assets" || ! -f "$SCRIPT_DIR/support/add_selected.sh" || ! -d "$SCRIPT_DIR/workflows/$ADD_NAME" ]]; then
  show_result $'安装包不完整。\n请保持解压后的所有文件在同一个文件夹中，再重新运行。'
  exit 1
fi

mkdir -p "$INSTALL_DIR" "$SERVICES_DIR" || exit 1
rm -rf "$INSTALL_DIR/runtime" "$INSTALL_DIR/support" "$INSTALL_DIR/assets"
/bin/cp -R "$SCRIPT_DIR/runtime" "$INSTALL_DIR/runtime"
/bin/cp -R "$SCRIPT_DIR/support" "$INSTALL_DIR/support"
/bin/cp -R "$SCRIPT_DIR/assets" "$INSTALL_DIR/assets"
/bin/chmod +x "$INSTALL_DIR/support/common.sh" "$INSTALL_DIR/support/add_selected.sh" "$INSTALL_DIR/support/check_selected.sh"

rm -rf "$SERVICES_DIR/$ADD_NAME" "$SERVICES_DIR/$CHECK_NAME"
/bin/cp -R "$SCRIPT_DIR/workflows/$ADD_NAME" "$SERVICES_DIR/$ADD_NAME"
/bin/cp -R "$SCRIPT_DIR/workflows/$CHECK_NAME" "$SERVICES_DIR/$CHECK_NAME"

if command -v xattr >/dev/null 2>&1; then
  xattr -dr com.apple.quarantine "$INSTALL_DIR" "$SERVICES_DIR/$ADD_NAME" "$SERVICES_DIR/$CHECK_NAME" >/dev/null 2>&1 || true
fi

if [[ -x /System/Library/CoreServices/pbs ]]; then
  /System/Library/CoreServices/pbs -flush >/dev/null 2>&1 || true
fi

show_result $'安装完成。\n\n现在在 Finder 里选中图片或文件夹 → 右键 →“快速操作”，即可看到：\n\n• 添加 Amazon AI 标签\n• 检查 Amazon AI 标签\n\n如果暂时没显示，点“快速操作 → 自定…”确认这两项已启用，或重新打开 Finder。'
exit 0
