# shellcheck shell=bash
check_commands() {
  info "Checking required commands..."
  if ! command -v gcloud &>/dev/null; then
    error "Required command not found: gcloud"
  fi
  info "All required commands are available."
}
