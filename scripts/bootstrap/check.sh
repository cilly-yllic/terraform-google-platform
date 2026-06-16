# shellcheck shell=bash
# `check` subcommand: 既存リソースの状態を検証する (作成は行わない)。
run_check() {
  check_commands
  check_gcloud_auth
  check_required_vars
  check_org_folder
  check_billing_account

  info "Checking Project ${BOOTSTRAP_PROJECT_ID}..."
  if project_exists; then
    info "Project ${BOOTSTRAP_PROJECT_ID} exists."
  else
    info "Project ${BOOTSTRAP_PROJECT_ID} does not exist (will be created on apply)."
  fi

  info "Checking Service Account ${TERRAFORM_PROJECT_FACTORY_SA_ID}..."
  if project_exists && sa_exists; then
    info "Service Account $(sa_email) exists."
  else
    info "Service Account $(sa_email) does not exist (will be created on apply)."
  fi

  info "Checking Workload Identity Pool ${WORKLOAD_IDENTITY_POOL_ID}..."
  if project_exists && pool_exists; then
    info "Workload Identity Pool ${WORKLOAD_IDENTITY_POOL_ID} exists."
  else
    info "Workload Identity Pool ${WORKLOAD_IDENTITY_POOL_ID} does not exist (will be created on apply)."
  fi

  info "Checking Workload Identity Provider ${WORKLOAD_IDENTITY_PROVIDER_ID}..."
  if project_exists && pool_exists && provider_exists; then
    info "Workload Identity Provider ${WORKLOAD_IDENTITY_PROVIDER_ID} exists."
  else
    info "Workload Identity Provider ${WORKLOAD_IDENTITY_PROVIDER_ID} does not exist (will be created on apply)."
  fi

  if [[ -n "${BUDGET_AMOUNT:-}" ]]; then
    if project_exists; then
      info "Checking Budget '$(budget_display_name)'..."
      if budget_exists; then
        info "Budget '$(budget_display_name)' already exists."
      else
        info "Budget '$(budget_display_name)' does not exist (will be created on apply)."
      fi
    else
      info "Budget check deferred: bootstrap project does not exist yet. '$(budget_display_name)' will be created on apply."
    fi
  else
    info "BUDGET_AMOUNT not set. Budget creation will be skipped on apply."
  fi

  if [[ "${ENABLE_CLOUD_RUN_DEPLOY_SETUP:-false}" == "true" ]]; then
    info "Checking Cloud Run runtime SA $(runtime_sa_id)..."
    if project_exists && runtime_sa_exists; then
      info "Runtime SA $(runtime_sa_email) exists."
    else
      info "Runtime SA $(runtime_sa_email) does not exist (will be created on apply)."
    fi

    info "Checking Cloud Run deploy SA $(deploy_sa_id)..."
    if project_exists && deploy_sa_exists; then
      info "Deploy SA $(deploy_sa_email) exists."
    else
      info "Deploy SA $(deploy_sa_email) does not exist (will be created on apply)."
    fi

    info "Checking GitHub WIF Provider $(github_provider_id)..."
    if project_exists && pool_exists && github_provider_exists; then
      info "GitHub WIF Provider $(github_provider_id) exists."
    else
      info "GitHub WIF Provider $(github_provider_id) does not exist (will be created on apply)."
    fi

    info "Checking org policy override 'iam.allowedPolicyMemberDomains' (allowAll: true)..."
    if project_exists && org_policy_allow_all_users_overridden; then
      info "Override is in place (allUsers can be bound as Cloud Run invoker)."
    else
      info "Override is NOT set on ${BOOTSTRAP_PROJECT_ID} (will be applied on apply)."
    fi

    local secret
    for secret in tfc-notification-secret github-app-private-key; do
      info "Checking runtime secret container '${secret}'..."
      if project_exists && runtime_secret_exists "${secret}"; then
        info "  Container '${secret}' exists."
      else
        info "  Container '${secret}' does not exist (will be created on apply)."
      fi
    done
  else
    info "ENABLE_CLOUD_RUN_DEPLOY_SETUP not set. Cloud Run deploy resource creation will be skipped on apply."
  fi

  info "Check completed."
}
