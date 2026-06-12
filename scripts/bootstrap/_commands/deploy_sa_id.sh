# shellcheck shell=bash
deploy_sa_id() {
  echo "${CLOUD_RUN_DEPLOY_SA_ID:-cloud-run-router-deploy}"
}
