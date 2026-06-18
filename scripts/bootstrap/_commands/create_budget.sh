# shellcheck shell=bash
# BUDGET_AMOUNT が設定されている場合のみ Budget を作成する。
# BUDGET_SCOPE=project (default) なら Bootstrap Project 専用、
# billing-account なら billing account 全体を監視する。
create_budget() {
  if [[ -z "${BUDGET_AMOUNT:-}" ]]; then
    info "BUDGET_AMOUNT not set. Skipping Budget creation."
    return
  fi

  local display_name
  display_name="$(budget_display_name)"
  local currency="${BUDGET_CURRENCY:-USD}"
  local scope="${BUDGET_SCOPE:-project}"
  local thresholds="${BUDGET_THRESHOLDS:-0.1,0.3,0.5,0.9,1.0}"

  info "Creating Budget '${display_name}' (${BUDGET_AMOUNT} ${currency}, scope=${scope})..."

  if budget_exists; then
    info "Budget '${display_name}' already exists. Skipping."
    return
  fi

  local cmd=(
    gcloud billing budgets create
    --billing-account="${BOOTSTRAP_BILLING_ACCOUNT_ID}"
    --project="${BOOTSTRAP_PROJECT_ID}"
    --display-name="${display_name}"
    --budget-amount="${BUDGET_AMOUNT}${currency}"
  )

  local threshold
  IFS=',' read -ra threshold_arr <<< "${thresholds}"
  for threshold in "${threshold_arr[@]}"; do
    threshold="${threshold// /}"
    [[ -z "${threshold}" ]] && continue
    cmd+=(--threshold-rule="percent=${threshold}")
  done

  case "${scope}" in
    project)
      local project_number
      project_number="$(gcloud projects describe "${BOOTSTRAP_PROJECT_ID}" \
        --format='value(projectNumber)')"
      cmd+=(--filter-projects="projects/${project_number}")
      ;;
    billing-account)
      : # No project filter -> whole billing account
      ;;
    *)
      error "Unknown BUDGET_SCOPE: ${scope}. Use 'project' or 'billing-account'."
      ;;
  esac

  "${cmd[@]}"

  info "Budget '${display_name}' created."
}
