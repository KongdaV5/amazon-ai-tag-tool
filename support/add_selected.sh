#!/bin/bash
# Finder Quick Action: add Amazon AI metadata to copies of selected images/folders.

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

TIMESTAMP="$(date '+%Y%m%d_%H%M%S')"
TOTAL_COUNT=0
SUCCESS_COUNT=0
ALREADY_COUNT=0
FAILED_COUNT=0
UNSUPPORTED_COUNT=0
FAILURE_PREVIEW=()
OUTPUT_ROOTS_FILE="${TMPDIR:-/tmp}/amazon_ai_outputs_$$.txt"
: > "$OUTPUT_ROOTS_FILE"

record_output_root() {
  local root="$1"
  printf '%s\n' "$root" >> "$OUTPUT_ROOTS_FILE"
}

process_image() {
  local file="$1"
  local destination="$2"
  local output_root="$3"
  local destination_dir subject_before subject_after error_text read_code write_output write_code verify_code was_already_tagged status

  (( TOTAL_COUNT++ ))
  destination_dir="$(dirname "$destination")"
  status=''
  subject_after=''
  error_text=''
  was_already_tagged=0

  mkdir -p "$destination_dir" || return 1
  record_output_root "$output_root"

  if ! /bin/cp -p "$file" "$destination" 2>/dev/null; then
    status='失败'
    error_text='复制原图失败'
    (( FAILED_COUNT++ ))
  else
    /bin/chmod u+w "$destination" 2>/dev/null || true
    subject_before="$(run_exiftool -m -s3 -sep '|||' -XMP-dc:Subject "$destination" 2>&1)"
    read_code=$?

    if (( read_code != 0 )); then
      status='失败'
      error_text="ExifTool 读取失败：$subject_before"
      (( FAILED_COUNT++ ))
    else
      if subject_has_tag "$subject_before"; then
        was_already_tagged=1
      else
        write_output="$(run_exiftool -m -P -overwrite_original "-XMP-dc:Subject+=$TAG_VALUE" "$destination" 2>&1)"
        write_code=$?
        if (( write_code != 0 )); then
          status='失败'
          error_text="ExifTool 写入失败：$write_output"
          (( FAILED_COUNT++ ))
        fi
      fi

      if [[ "$status" != '失败' ]]; then
        subject_after="$(run_exiftool -m -s3 -sep '|||' -XMP-dc:Subject "$destination" 2>&1)"
        verify_code=$?
        if (( verify_code != 0 )); then
          status='失败'
          error_text="ExifTool 校验失败：$subject_after"
          (( FAILED_COUNT++ ))
        elif subject_has_tag "$subject_after"; then
          if (( was_already_tagged == 1 )); then
            status='原本已有标签'
            (( ALREADY_COUNT++ ))
          else
            status='写入成功'
            (( SUCCESS_COUNT++ ))
          fi
        else
          status='失败'
          error_text="写入后校验失败。当前 Subject：$subject_after"
          (( FAILED_COUNT++ ))
        fi
      fi
    fi
  fi

  if [[ "$status" == '失败' && ${#FAILURE_PREVIEW[@]} -lt 5 ]]; then
    FAILURE_PREVIEW+=("$(basename "$file")：$error_text")
  fi
}

process_file_selection() {
  local file="$1"
  local parent output_root destination
  if ! is_supported_image "$file"; then
    (( UNSUPPORTED_COUNT++ ))
    return 0
  fi
  parent="$(cd "$(dirname "$file")" && pwd -P)"
  output_root="$parent/Amazon_AI_Tagged_$TIMESTAMP"
  mkdir -p "$output_root"
  destination="$output_root/$(basename "$file")"
  process_image "$file" "$destination" "$output_root"
}

process_folder_selection() {
  local folder="$1"
  local source_folder output_root file relative destination found
  source_folder="$(cd "$folder" && pwd -P)"
  output_root="$source_folder/Amazon_AI_Tagged_$TIMESTAMP"
  found=0

  while IFS= read -r -d '' file; do
    found=1
    relative="${file#$source_folder/}"
    destination="$output_root/$relative"
    process_image "$file" "$destination" "$output_root"
  done < <(
    /usr/bin/find "$source_folder" -mindepth 1 \
      \( -type d -name 'Amazon_AI_Tagged_*' -prune \) -o \
      \( -type f \( \
        -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o \
        -iname '*.tif' -o -iname '*.tiff' -o -iname '*.webp' \
      \) -print0 \)
  )

  if (( found == 0 )); then
    (( UNSUPPORTED_COUNT++ ))
  fi
}

for item in "$@"; do
  if [[ -f "$item" ]]; then
    process_file_selection "$item"
  elif [[ -d "$item" ]]; then
    process_folder_selection "$item"
  else
    (( UNSUPPORTED_COUNT++ ))
  fi
done

if (( TOTAL_COUNT == 0 )); then
  /bin/rm -f "$OUTPUT_ROOTS_FILE"
  show_alert '没有找到支持的图片。支持 JPG、JPEG、PNG、TIF、TIFF、WEBP。' warning
  exit 0
fi

OUTPUT_ROOTS="$(/usr/bin/sort -u "$OUTPUT_ROOTS_FILE" 2>/dev/null)"
OUTPUT_ROOT_COUNT="$(printf '%s\n' "$OUTPUT_ROOTS" | /usr/bin/awk 'NF{c++} END{print c+0}')"
FIRST_OUTPUT="$(printf '%s\n' "$OUTPUT_ROOTS" | /usr/bin/awk 'NF{print; exit}')"
/bin/rm -f "$OUTPUT_ROOTS_FILE"

SUMMARY=$'处理完成。\n\n'
SUMMARY+="写入成功：$SUCCESS_COUNT"$'\n'
SUMMARY+="原本已有：$ALREADY_COUNT"$'\n'
SUMMARY+="失败：$FAILED_COUNT"$'\n'
SUMMARY+="总图片数：$TOTAL_COUNT"$'\n'
if (( UNSUPPORTED_COUNT > 0 )); then
  SUMMARY+="无支持图片的选中项：$UNSUPPORTED_COUNT"$'\n'
fi
SUMMARY+=$'\n原始图片没有被修改。\n'
if (( OUTPUT_ROOT_COUNT == 1 )); then
  SUMMARY+=$'\n输出目录：\n'
  SUMMARY+="$FIRST_OUTPUT"
else
  SUMMARY+=$'\n输出到了 '
  SUMMARY+="$OUTPUT_ROOT_COUNT"
  SUMMARY+=$' 个对应目录下的 Amazon_AI_Tagged 文件夹。'
fi

if (( FAILED_COUNT > 0 )); then
  SUMMARY+=$'\n\n前几个错误：\n'
  for failure_line in "${FAILURE_PREVIEW[@]}"; do
    SUMMARY+="• $failure_line"$'\n'
  done
  show_alert "$SUMMARY" warning
else
  show_alert "$SUMMARY" informational
fi

if [[ -n "$FIRST_OUTPUT" ]]; then
  reveal_path "$FIRST_OUTPUT"
fi
exit 0
