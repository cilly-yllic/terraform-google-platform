# shellcheck shell=bash
runtime_sa_id() {
  echo "${CLOUD_RUN_RUNTIME_SA_ID:-cloud-run-router-runtime}"
}
