# shellcheck shell=bash
create_project() {
  info "Creating Project ${BOOTSTRAP_PROJECT_ID}..."
  if project_exists; then
    info "Project ${BOOTSTRAP_PROJECT_ID} already exists. Skipping."
    return
  fi

  local parent_flag
  if [[ -n "${BOOTSTRAP_FOLDER_ID:-}" ]]; then
    parent_flag="--folder=${BOOTSTRAP_FOLDER_ID}"
  else
    parent_flag="--organization=${ORGANIZATION_ID}"
  fi

  gcloud projects create "${BOOTSTRAP_PROJECT_ID}" \
    --name="${BOOTSTRAP_PROJECT_NAME}" \
    "${parent_flag}"

  info "Project ${BOOTSTRAP_PROJECT_ID} created."
  propagate_sleep low "project to be ready for billing/API operations"
}
