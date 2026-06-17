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

  ensure_folder
  create_project
  link_billing
  enable_apis
  # service project は auto_create_network=false で作られるため、placement
  # (folder/org) に compute.skipDefaultNetworkCreation を enforce して default
  # network を作らせない (作成時の Compute API 依存 = 403 を根本回避)。
  # enable_apis 後に置くのは org-policy set-policy の quota project (bootstrap
  # project) で orgpolicy API が有効になっている必要があるため。
  set_skip_default_network_policy
  create_service_account
  grant_iam
  create_workload_identity_pool
  create_workload_identity_provider
  grant_wif_impersonation
  create_budget

  if [[ "${ENABLE_CLOUD_RUN_DEPLOY_SETUP:-false}" == "true" ]]; then
    info "ENABLE_CLOUD_RUN_DEPLOY_SETUP=true — provisioning Cloud Run deploy resources..."
    enable_cloud_run_deploy_apis
    # `allUsers → roles/run.invoker` を deploy 時に付けるための org policy override。
    # アプリ層は HMAC で保護されているので IAM 層を public にしても安全。詳細は
    # _commands/override_org_policy_allow_all_users.sh のヘッダコメント参照。
    override_org_policy_allow_all_users
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
