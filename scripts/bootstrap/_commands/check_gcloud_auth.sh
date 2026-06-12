# shellcheck shell=bash
check_gcloud_auth() {
  info "Checking gcloud authentication..."
  if ! gcloud auth print-access-token &>/dev/null; then
    error "Not authenticated with gcloud. Run: gcloud auth login"
  fi
  info "gcloud is authenticated."
}
