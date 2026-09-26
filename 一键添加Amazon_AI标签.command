#!/bin/bash
# Amazon AI Metadata One-Click Tool for macOS.
# Keeps originals untouched and writes XMP-dc:Subject=contains-synthetic-performer to copies.

set -u

TOOL_TITLE='Amazon AI 标签工具'
TAG_VALUE='contains-synthetic-performer'
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
RUNTIME_DIR="$SCRIPT_DIR/runtime"
EXIFTOOL_PL="$RUNTIME_DIR/exiftool.pl"
ICON_PATH="$SCRIPT_DIR/assets/Amazon_AI_Tag.icns"

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

choose_folder() {
  /usr/bin/osascript <<'APPLESCRIPT' 2>/dev/null
tell application "System Events"
    activate
    set chosenFolder to choose folder with prompt "选择需要添加 Amazon AI 人物标签的图片文件夹（自动处理子文件夹）"
    return POSIX path of chosenFolder
end tell
APPLESCRIPT
}

if [[ -x /usr/bin/perl && -f "$EXIFTOOL_PL" ]]; then
  EXIFTOOL_MODE='bundled'
elif command -v exiftool >/dev/null 2>&1; then
  EXIFTOOL_MODE='system'
else
  show_alert $'无法启动 ExifTool。\n\n工具包可能不完整，或当前 macOS 缺少 /usr/bin/perl。\n请重新解压完整工具包。' critical
  exit 1
fi

run_exiftool() {
  if [[ "$EXIFTOOL_MODE" == 'system' ]]; then
    command exiftool "$@"
  else
    /usr/bin/perl "$EXIFTOOL_PL" "$@"
  fi
}

VERSION="$(run_exiftool -ver 2>/dev/null)"
if [[ -z "$VERSION" ]]; then
  show_alert 'ExifTool 无法正常启动，请重新解压完整工具包。' critical
  exit 1
fi

if (( $# >= 1 )) && [[ -d "$1" ]]; then
  SOURCE_FOLDER="$(cd "$1" && pwd -P)"
else
  SOURCE_FOLDER="$(choose_folder)" || exit 0
  [[ -n "$SOURCE_FOLDER" ]] || exit 0
  SOURCE_FOLDER="$(cd "$SOURCE_FOLDER" && pwd -P)"
fi
SOURCE_FOLDER="${SOURCE_FOLDER%/}"

TIMESTAMP="$(date '+%Y%m%d_%H%M%S')"
OUTPUT_FOLDER="$SOURCE_FOLDER/Amazon_AI_Tagged_$TIMESTAMP"

mkdir -p "$OUTPUT_FOLDER" || {
  show_alert "无法创建输出目录：\n$OUTPUT_FOLDER" critical
  exit 1
}

SUCCESS_COUNT=0
ALREADY_COUNT=0
FAILED_COUNT=0
TOTAL_COUNT=0
FAILURE_PREVIEW=()

printf '%s\n' "Amazon AI 标签工具"
printf '%s\n' "ExifTool $VERSION"
printf '%s\n' "源目录：$SOURCE_FOLDER"
printf '%s\n' "输出目录：$OUTPUT_FOLDER"
printf '\n'

while IFS= read -r -d '' FILE; do
  (( TOTAL_COUNT++ ))
  RELATIVE_PATH="${FILE#$SOURCE_FOLDER/}"
  DESTINATION="$OUTPUT_FOLDER/$RELATIVE_PATH"
  DESTINATION_DIR="$(dirname "$DESTINATION")"
  STATUS=''
  ERROR_TEXT=''

  mkdir -p "$DESTINATION_DIR"

  if ! /bin/cp -p "$FILE" "$DESTINATION" 2>/dev/null; then
    STATUS='失败'
    ERROR_TEXT='复制原图失败'
    (( FAILED_COUNT++ ))
  else
    /bin/chmod u+w "$DESTINATION" 2>/dev/null || true

    SUBJECT_BEFORE="$(run_exiftool -m -s3 -sep '|||' -XMP-dc:Subject "$DESTINATION" 2>&1)"
    READ_CODE=$?

    if (( READ_CODE != 0 )); then
      STATUS='失败'
      ERROR_TEXT="ExifTool 读取失败：$SUBJECT_BEFORE"
      (( FAILED_COUNT++ ))
    else
      case "|||$SUBJECT_BEFORE|||" in
        *"|||$TAG_VALUE|||"*) WAS_ALREADY_TAGGED=1 ;;
        *)
          WAS_ALREADY_TAGGED=0
          WRITE_OUTPUT="$(run_exiftool -m -P -overwrite_original "-XMP-dc:Subject+=$TAG_VALUE" "$DESTINATION" 2>&1)"
          WRITE_CODE=$?
          if (( WRITE_CODE != 0 )); then
            STATUS='失败'
            ERROR_TEXT="ExifTool 写入失败：$WRITE_OUTPUT"
            (( FAILED_COUNT++ ))
          fi
          ;;
      esac

      if [[ "$STATUS" != '失败' ]]; then
        SUBJECT_AFTER="$(run_exiftool -m -s3 -sep '|||' -XMP-dc:Subject "$DESTINATION" 2>&1)"
        VERIFY_CODE=$?
        if (( VERIFY_CODE != 0 )); then
          STATUS='失败'
          ERROR_TEXT="ExifTool 校验失败：$SUBJECT_AFTER"
          (( FAILED_COUNT++ ))
        else
          case "|||$SUBJECT_AFTER|||" in
            *"|||$TAG_VALUE|||"*)
              if (( WAS_ALREADY_TAGGED == 1 )); then
                STATUS='原本已有标签'
                (( ALREADY_COUNT++ ))
              else
                STATUS='写入成功'
                (( SUCCESS_COUNT++ ))
              fi
              ;;
            *)
              STATUS='失败'
              ERROR_TEXT="写入后校验失败。当前 Subject：$SUBJECT_AFTER"
              (( FAILED_COUNT++ ))
              ;;
          esac
        fi
      fi
    fi
  fi

  if [[ "$STATUS" == '失败' && ${#FAILURE_PREVIEW[@]} -lt 3 ]]; then
    FAILURE_PREVIEW+=("$(basename "$FILE")：$ERROR_TEXT")
  fi

  printf '[%s] %s  %s\n' "$TOTAL_COUNT" "$STATUS" "$RELATIVE_PATH"
done < <(
  /usr/bin/find "$SOURCE_FOLDER" \
    \( -type d -name 'Amazon_AI_Tagged_*' -prune \) -o \
    \( -type f \( \
      -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o \
      -iname '*.tif' -o -iname '*.tiff' -o -iname '*.webp' \
    \) -print0 \)
)

if (( TOTAL_COUNT == 0 )); then
  /bin/rm -rf "$OUTPUT_FOLDER"
  show_alert '没有找到支持的图片。支持 JPG、JPEG、PNG、TIF、TIFF、WEBP。' warning
  exit 0
fi

SUMMARY=$'处理完成。\n\n'
SUMMARY+="写入成功：$SUCCESS_COUNT"$'\n'
SUMMARY+="原本已有：$ALREADY_COUNT"$'\n'
SUMMARY+="失败：$FAILED_COUNT"$'\n'
SUMMARY+="总文件数：$TOTAL_COUNT"$'\n\n'
SUMMARY+=$'原始图片没有被修改。\n\n输出目录：\n'
SUMMARY+="$OUTPUT_FOLDER"

if (( FAILED_COUNT > 0 )); then
  SUMMARY+=$'\n\n前几个错误：\n'
  for failure_line in "${FAILURE_PREVIEW[@]}"; do
    SUMMARY+="• $failure_line"$'\n'
  done
  show_alert "$SUMMARY" warning
else
  show_alert "$SUMMARY" informational
fi

/usr/bin/open "$OUTPUT_FOLDER" >/dev/null 2>&1 || true
exit 0
