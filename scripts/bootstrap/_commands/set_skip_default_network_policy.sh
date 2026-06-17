# shellcheck shell=bash
# org policy `compute.skipDefaultNetworkCreation` を placement (folder or org) に
# enforce する。
#
# なぜ必要か:
#   project-bootstrap module は project を `auto_create_network = false` で作る
#   (デフォルトネットワークを残さない security baseline)。provider はこれを実現
#   するため作成時にデフォルトネットワークを削除しようとするが、削除には対象
#   project で Compute Engine API が有効である必要があり、新規 project では未有効の
#   ため 403 "Compute Engine API has not been used in project ..." で落ちる。
#   このポリシーを enforce すると **デフォルトネットワークがそもそも作られない**
#   ため、削除も Compute API も不要になり問題が根本から消える。
#
# スコープ:
#   folder mode (FOLDER_ID あり) → その folder に enforce (配下の service project に
#   継承)。org-direct mode → org に enforce。grant_iam と同じ folder 優先。
#
# 権限要件:
#   caller に organization / folder スコープの roles/orgpolicy.policyAdmin が必要
#   (project スコープには付与できない constraint)。詳細は scripts/README.md
#   「事前権限 (caller 側)」参照。
#
# 冪等性:
#   `gcloud org-policies set-policy` は同 spec で再実行しても no-op。
set_skip_default_network_policy() {
  local resource
  if [[ -n "${FOLDER_ID:-}" ]]; then
    resource="folders/${FOLDER_ID}"
  else
    resource="organizations/${ORGANIZATION_ID}"
  fi

  info "Enforcing org policy 'compute.skipDefaultNetworkCreation' on ${resource}..."
  info "  Reason: project は auto_create_network=false で作られるため、default network を作らせない (Compute API 不要化)"

  local policy_file
  policy_file="$(mktemp)"
  cat > "${policy_file}" <<EOF
name: ${resource}/policies/compute.skipDefaultNetworkCreation
spec:
  rules:
    - enforce: true
EOF

  # --project は API call の quota / billing project。bootstrap project には
  # orgpolicy API を有効化済み (REQUIRED_APIS)。target resource は policy file の
  # name: で指定済み。
  if ! gcloud org-policies set-policy "${policy_file}" \
    --project="${BOOTSTRAP_PROJECT_ID}" \
    --quiet > /dev/null; then
    rm -f "${policy_file}"
    error "Failed to enforce 'compute.skipDefaultNetworkCreation' on ${resource}. The caller needs roles/orgpolicy.policyAdmin on the org/folder. See scripts/README.md '事前権限 (caller 側)'."
  fi
  rm -f "${policy_file}"

  info "Org policy enforced (default network creation disabled for new projects under ${resource})."
}
