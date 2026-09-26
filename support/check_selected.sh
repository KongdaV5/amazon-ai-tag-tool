#!/bin/bash
# Finder Quick Action: read-only check for Amazon AI metadata.

set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
. "$SCRIPT_DIR/common.sh"

VERSION="$(run_exiftool -ver 2>/dev/null)"
if [[ -z "$VERSION" ]]; then
  show_alert 'ExifTool 无法正常启动，请重新运行安装脚本。' critical
  exit 1
fi

if (( $# == 0 )); then
  show_alert '没有收到 Finder 选中的文件或文件夹。' warning
  exit 0
fi

TOTAL_COUNT=0
TAGGED_COUNT=0
MISSING_COUNT=0
FAILED_COUNT=0
UNSUPPORTED_COUNT=0
MISSING_PREVIEW=()
FAILED_PREVIEW=()

check_image() {
  local file="$1"
  local subject code
  (( TOTAL_COUNT++ ))
  subject="$(run_exiftool -m -s3 -sep '|||' -XMP-dc:Subject "$file" 2>&1)"
  code=$?

  if (( code != 0 )); then
    (( FAILED_COUNT++ ))
    if [[ ${#FAILED_PREVIEW[@]} -lt 5 ]]; then
      FAILED_PREVIEW+=("$(basename "$file")")
    fi
  elif subject_has_tag "$subject"; then
    (( TAGGED_COUNT++ ))
  else
    (( MISSING_COUNT++ ))
    if [[ ${#MISSING_PREVIEW[@]} -lt 8 ]]; then
      MISSING_PREVIEW+=("$(basename "$file")")
    fi
  fi
}

check_folder() {
  local folder="$1"
  local file found folder_name
  found=0
  folder_name="$(basename "$folder")"

  # Normal source folders ignore generated Amazon_AI_Tagged_* subfolders so source
  # images and tagged copies are not counted together. A selected output folder is checked normally.
  if [[ "$folder_name" == Amazon_AI_Tagged_* ]]; then
    while IFS= read -r -d '' file; do
      found=1
      check_image "$file"
    done < <(
      /usr/bin/find "$folder" -type f \( \
        -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o \
        -iname '*.tif' -o -iname '*.tiff' -o -iname '*.webp' \
      \) -print0
    )
  else
    while IFS= read -r -d '' file; do
      found=1
      check_image "$file"
    done < <(
      /usr/bin/find "$folder" -mindepth 1 \
        \( -type d -name 'Amazon_AI_Tagged_*' -prune \) -o \
        \( -type f \( \
          -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o \
          -iname '*.tif' -o -iname '*.tiff' -o -iname '*.webp' \
        \) -print0 \)
    )
  fi

  if (( found == 0 )); then
    (( UNSUPPORTED_COUNT++ ))
  fi
}

for item in "$@"; do
  if [[ -f "$item" ]]; then
    if is_supported_image "$item"; then
      check_image "$item"
    else
      (( UNSUPPORTED_COUNT++ ))
    fi
  elif [[ -d "$item" ]]; then
    check_folder "$item"
  else
    (( UNSUPPORTED_COUNT++ ))
  fi
done

if (( TOTAL_COUNT == 0 )); then
  show_alert '没有找到支持的图片。支持 JPG、JPEG、PNG、TIF、TIFF、WEBP。' warning
  exit 0
fi

SUMMARY=$'检查完成（只读取，没有修改图片）。\n\n'
SUMMARY+="已标记：$TAGGED_COUNT"$'\n'
SUMMARY+="未标记：$MISSING_COUNT"$'\n'
SUMMARY+="读取失败：$FAILED_COUNT"$'\n'
SUMMARY+="总图片数：$TOTAL_COUNT"

if (( UNSUPPORTED_COUNT > 0 )); then
  SUMMARY+=$'\n'
  SUMMARY+="无支持图片的选中项：$UNSUPPORTED_COUNT"
fi

if (( MISSING_COUNT > 0 )); then
  SUMMARY+=$'\n\n未标记文件（最多显示 8 个）：\n'
  for file_name in "${MISSING_PREVIEW[@]}"; do
    SUMMARY+="• $file_name"$'\n'
  done
fi

if (( FAILED_COUNT > 0 )); then
  SUMMARY+=$'\n读取失败文件（最多显示 5 个）：\n'
  for file_name in "${FAILED_PREVIEW[@]}"; do
    SUMMARY+="• $file_name"$'\n'
  done
fi

if (( MISSING_COUNT > 0 || FAILED_COUNT > 0 )); then
  show_alert "$SUMMARY" warning
else
  show_alert "$SUMMARY" informational
fi
exit 0
