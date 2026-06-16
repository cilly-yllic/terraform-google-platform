# shellcheck shell=bash
# `iam.allowedPolicyMemberDomains` (Domain Restricted Sharing) constraint を
# bootstrap project スコープで `allowAll: true` に上書きする。
#
# なぜ必要か:
#   Cloud Run Router は TFC notification の受け口なので、TFC が verification
#   POST を送れるよう `allUsers → roles/run.invoker` の IAM binding が必要。
#   `gcloud run deploy --allow-unauthenticated` はこの binding を試みるが、
#   org policy で domain restricted sharing が enforce されていると
#   "Setting IAM policy failed" の warning を出して silent fail する。
#   結果 Cloud Run service 自体は up しても外部からは 403 が返り、TFC の
#   notification 登録時の verification POST も同じく 403 で落ちて
#   `Verification failed with the error: 403` になる。
#
# なぜ安全か:
#   `allUsers` を許可するのは IAM 層 (TCP 到達可) だけで、アプリ層は
#   `cloud-run-router/src/routes/webhook/index.ts` で
#   `X-TFE-Notification-Signature` の HMAC-SHA512 を必ず検証している
#   (`tfcNotificationSecret` を知らない限り 401 invalid_signature)。
#   GitHub / Stripe webhook receiver と同じ shared-secret パターン。
#
# 権限要件:
#   `roles/orgpolicy.policyAdmin` を **organization or folder スコープで**
#   持つ principal で実行する必要がある。このロールは GCP の仕様上
#   project スコープには付与できない (project レベルに add-iam-policy-binding
#   で付けようとすると INVALID_ARGUMENT: "Role roles/orgpolicy.policyAdmin
#   is not supported for this resource" になる)。
#   通常 bootstrap を回す org / folder admin であれば持っている。
#   詳細は scripts/README.md 「事前権限 (caller 側)」セクション参照。
#
# 冪等性:
#   `gcloud org-policies set-policy` は同 spec で再実行しても no-op。
override_org_policy_allow_all_users() {
  info "Overriding org policy 'iam.allowedPolicyMemberDomains' on ${BOOTSTRAP_PROJECT_ID} (allowAll: true)..."
  info "  Reason: Cloud Run Router's public /webhook (HMAC-verified at app layer; see cloud-run-router/src/routes/webhook/index.ts)"

  local policy_file
  policy_file="$(mktemp)"
  cat > "${policy_file}" <<EOF
name: projects/${BOOTSTRAP_PROJECT_ID}/policies/iam.allowedPolicyMemberDomains
spec:
  rules:
    - allowAll: true
EOF

  # --project は **quota / billing project** を指定するフラグ。
  # target resource は policy file 内の `name:` で指定済みだが、API call の
  # quota はアクティブプロジェクト (gcloud config) にデフォルトで落ちる。
  # `mdn-infra-bootstrap-001` 以外をアクティブにしている caller で
  # `orgpolicy.googleapis.com` 未 enable のプロジェクトに quota が落ちて
  # PERMISSION_DENIED になるのを避けるため、明示的に bootstrap project を渡す。
  if ! gcloud org-policies set-policy "${policy_file}" \
    --project="${BOOTSTRAP_PROJECT_ID}" \
    --quiet > /dev/null; then
    rm -f "${policy_file}"
    error "Failed to override 'iam.allowedPolicyMemberDomains' on ${BOOTSTRAP_PROJECT_ID}. The caller needs roles/orgpolicy.policyAdmin on the project (or parent org/folder)."
  fi
  rm -f "${policy_file}"

  info "Org policy override applied."
}
