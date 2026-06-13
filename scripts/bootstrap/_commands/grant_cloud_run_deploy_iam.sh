# shellcheck shell=bash
# Cloud Run deploy SA / runtime SA に必要な IAM role を付与する。
#
#   Deploy SA (project レベル):
#     run.developer                     : Cloud Run service の deploy / 更新
#     artifactregistry.writer           : container image を push
#     cloudbuild.builds.editor          : `gcloud builds submit` で Cloud Build job 発行
#     storage.admin                     : Cloud Build が source upload に GCS bucket を使う
#     iam.serviceAccountTokenCreator    : runtime SA の token を発行 (Cloud Run service 起動時の impersonation)
#     secretmanager.secretVersionAdder  : deploy workflow が GitHub Secret から
#                                         tfc-notification-secret / github-app-private-key の
#                                         新 version を Secret Manager に push する
#   Deploy SA → Runtime SA:
#     iam.serviceAccountUser            : Cloud Run service の `--service-account=<runtime>` 指定用
#   Deploy SA → Cloud Build runner SA (Compute default / legacy cloudbuild):
#     iam.serviceAccountUser            : `gcloud builds submit` が build job を Cloud Build
#                                         runner SA として起動するため、deploy 主体は
#                                         runner SA に "act as" する権限が必要。
#                                         2024-04 以降の project は Compute Engine default SA
#                                         (`<PROJECT_NUMBER>-compute@developer.gserviceaccount.com`)
#                                         を runner として使う。古い project は legacy
#                                         `<PROJECT_NUMBER>@cloudbuild.gserviceaccount.com`。
#                                         両方に binding を試みる (存在しない方は skip)。
#   Runtime SA (project レベル):
#     secretmanager.secretAccessor      : Cloud Run service runtime での secret 読み取り
grant_cloud_run_deploy_iam() {
  info "Granting IAM roles to Cloud Run deploy / runtime SAs..."

  local deploy_member runtime_member
  deploy_member="serviceAccount:$(deploy_sa_email)"
  runtime_member="serviceAccount:$(runtime_sa_email)"

  local deploy_project_roles=(
    roles/run.developer
    roles/artifactregistry.writer
    roles/cloudbuild.builds.editor
    roles/storage.admin
    roles/iam.serviceAccountTokenCreator
    roles/secretmanager.secretVersionAdder
  )
  for role in "${deploy_project_roles[@]}"; do
    info "  Deploy SA / Project: ${role}"
    gcloud projects add-iam-policy-binding "${BOOTSTRAP_PROJECT_ID}" \
      --member="${deploy_member}" \
      --role="${role}" \
      --quiet
  done

  info "  Deploy SA / Runtime SA: roles/iam.serviceAccountUser"
  gcloud iam service-accounts add-iam-policy-binding "$(runtime_sa_email)" \
    --project="${BOOTSTRAP_PROJECT_ID}" \
    --member="${deploy_member}" \
    --role="roles/iam.serviceAccountUser" \
    --quiet

  # Cloud Build runner SA への iam.serviceAccountUser 付与。
  # 2024-04 以降の project は Compute Engine default SA を build runner に
  # 使うので必須。legacy cloudbuild SA は古い project 向け (存在しない場合は skip)。
  local project_number
  project_number="$(gcloud projects describe "${BOOTSTRAP_PROJECT_ID}" \
    --format='value(projectNumber)')"

  local compute_default_sa="${project_number}-compute@developer.gserviceaccount.com"
  info "  Deploy SA / Compute default SA (Cloud Build runner): roles/iam.serviceAccountUser"
  if ! gcloud iam service-accounts add-iam-policy-binding "${compute_default_sa}" \
    --project="${BOOTSTRAP_PROJECT_ID}" \
    --member="${deploy_member}" \
    --role="roles/iam.serviceAccountUser" \
    --quiet 2>/dev/null; then
    info "    (Compute default SA not found — skipped)"
  fi

  local cloudbuild_default_sa="${project_number}@cloudbuild.gserviceaccount.com"
  info "  Deploy SA / Cloud Build legacy SA: roles/iam.serviceAccountUser"
  if ! gcloud iam service-accounts add-iam-policy-binding "${cloudbuild_default_sa}" \
    --project="${BOOTSTRAP_PROJECT_ID}" \
    --member="${deploy_member}" \
    --role="roles/iam.serviceAccountUser" \
    --quiet 2>/dev/null; then
    info "    (legacy cloudbuild SA not found — skipped)"
  fi

  local runtime_project_roles=(
    roles/secretmanager.secretAccessor
  )
  for role in "${runtime_project_roles[@]}"; do
    info "  Runtime SA / Project: ${role}"
    gcloud projects add-iam-policy-binding "${BOOTSTRAP_PROJECT_ID}" \
      --member="${runtime_member}" \
      --role="${role}" \
      --quiet
  done

  info "Cloud Run deploy IAM roles granted."
}
