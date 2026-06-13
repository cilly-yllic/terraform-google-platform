#!/usr/bin/env bash
#
# Bootstrap script entry point (thin dispatcher).
#
# 実体ロジックは以下に分割されている:
#   scripts/bootstrap/<subcommand>.sh        - サブコマンドの run_* 関数
#   scripts/bootstrap/_commands/<func>.sh    - 各サブ関数 (1 関数 = 1 ファイル)
#
# 起動時に _commands/*.sh と <subcommand>.sh をすべて source してから、
# CLI 引数を見て対応する run_* 関数を呼ぶ。
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
BOOTSTRAP_DIR="${SCRIPT_DIR}/bootstrap"

###############################################################################
# Source order:
#   1. _commands/_constants.sh  - 配列・固定値 (ENV_FILE, REQUIRED_VARS, ...)
#   2. _commands/_log.sh        - info / error
#   3. _commands/*.sh           - 残りすべて (alphabetical)
#   4. <subcommand>.sh          - run_apply / run_check / run_print_env /
#                                 run_dry_run / run_init / show_help
###############################################################################

# shellcheck source=bootstrap/_commands/_constants.sh
source "${BOOTSTRAP_DIR}/_commands/_constants.sh"
# shellcheck source=bootstrap/_commands/_log.sh
source "${BOOTSTRAP_DIR}/_commands/_log.sh"

for f in "${BOOTSTRAP_DIR}/_commands"/*.sh; do
  case "$(basename "${f}")" in
    _constants.sh|_log.sh) continue ;;  # already sourced
  esac
  # shellcheck source=/dev/null
  source "${f}"
done

for f in "${BOOTSTRAP_DIR}"/*.sh; do
  # shellcheck source=/dev/null
  source "${f}"
done

###############################################################################
# main: CLI parsing + dispatch
###############################################################################

main() {
  local subcommand=""
  local do_help=false
  local do_dry_run=false
  local do_init=false
  local init_format=""

  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help)
        do_help=true
        shift
        ;;
      -d|--dry-run)
        do_dry_run=true
        shift
        ;;
      --init=*)
        do_init=true
        init_format="${1#--init=}"
        shift
        ;;
      -i|--init)
        do_init=true
        shift
        ;;
      check|apply|print-env)
        subcommand="$1"
        shift
        ;;
      *)
        error "Unknown argument: $1. Run '$0 --help' for usage."
        ;;
    esac
  done

  # --help takes highest priority
  if [[ "${do_help}" == "true" ]]; then
    show_help
    exit 0
  fi

  # --init runs without loading .env
  if [[ "${do_init}" == "true" ]]; then
    if [[ -n "${subcommand}" ]]; then
      echo "[WARN]  Subcommand '${subcommand}' is ignored when --init is specified." >&2
    fi
    run_init "${init_format}"
    exit 0
  fi

  # --dry-run does not require subcommand
  if [[ "${do_dry_run}" == "true" ]]; then
    if [[ -n "${subcommand}" ]]; then
      echo "[WARN]  Subcommand '${subcommand}' is ignored when --dry-run is specified." >&2
    fi
    run_dry_run
    exit $?
  fi

  # Subcommand required from here
  if [[ -z "${subcommand}" ]]; then
    echo "Error: subcommand required. Run '$0 --help' for usage." >&2
    echo "" >&2
    show_help >&2
    exit 1
  fi

  load_env

  case "${subcommand}" in
    check)
      run_check
      ;;
    apply)
      run_apply
      ;;
    print-env)
      run_print_env
      ;;
    *)
      error "Unknown subcommand: ${subcommand}. Run '$0 --help' for usage."
      ;;
  esac
}

main "$@"
