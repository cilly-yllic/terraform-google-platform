# shellcheck shell=bash
budget_display_name() {
  echo "${BUDGET_DISPLAY_NAME:-${BOOTSTRAP_PROJECT_NAME} Budget}"
}
