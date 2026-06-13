# shellcheck shell=bash
# 値を伏字化 (先頭2文字 + *** + 末尾2文字)。
# 4 文字以下なら全マスク。dry-run で機密値を晒さないために使う。
mask_value() {
  local val="$1"
  if [[ -z "${val}" ]]; then
    echo "(not set)"
    return
  fi
  local len=${#val}
  if [[ ${len} -le 4 ]]; then
    echo "****"
  else
    echo "${val:0:2}***${val: -2}"
  fi
}
