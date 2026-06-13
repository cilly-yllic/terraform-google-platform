# shellcheck shell=bash
# `apply` subcommand: 全ての bootstrap リソースを作成する (冪等)。
# ENABLE_CLOUD_RUN_DEPLOY_SETUP=true なら Cloud Run deploy 用リソースも作る。
run_apply() {
  check_commands
  check_gcloud_auth
  check_required_vars
  check_org_folder
  check_billing_account

  confirm_apply

  create_project
  link_billing
  enable_apis
  create_service_account
  grant_iam
  create_workload_identity_pool
  create_workload_identity_provider
  grant_wif_impersonation
  create_budget

  if [[ "${ENABLE_CLOUD_RUN_DEPLOY_SETUP:-false}" == "true" ]]; then
    info "ENABLE_CLOUD_RUN_DEPLOY_SETUP=true — provisioning Cloud Run deploy resources..."
    enable_cloud_run_deploy_apis
    create_cloud_run_runtime_sa
    create_cloud_run_deploy_sa
    grant_cloud_run_deploy_iam
    create_cloud_run_runtime_secret_containers
    create_github_wif_provider
    grant_github_wif_binding
  fi

  info "Bootstrap apply completed."
  echo ""
  print_env
}
