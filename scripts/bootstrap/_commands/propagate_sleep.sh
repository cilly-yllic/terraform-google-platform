# shellcheck shell=bash
# GCP の eventual-consistency 伝播を吸収するための sleep。
#   high → 10s (critical: SA create → IAM binding)
#   med  → 5s  (moderate: API enable → next API call, WIF pool → provider)
#   low  → 1s  (minor: project create, billing link, WIF provider → IAM)
propagate_sleep() {
  local level="$1"
  local reason="${2:-propagation}"
  local seconds
  case "${level}" in
    high) seconds=10 ;;
    med)  seconds=5 ;;
    low)  seconds=1 ;;
    *)    seconds=0 ;;
  esac
  if (( seconds > 0 )); then
    info "Waiting ${seconds}s for ${reason}..."
    sleep "${seconds}"
  fi
}
