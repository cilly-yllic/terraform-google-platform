# ---------------------------------------------------------------------------
# Users – project-level roles
# ---------------------------------------------------------------------------

locals {
  user_base_roles = flatten([
    for user in var.users : {
      key    = "${user.email}-roles/${user.role}"
      member = "user:${user.email}"
      role   = "roles/${user.role}"
    }
  ])

  user_deploy_roles = flatten([
    for user in var.users : [
      for role in ["roles/cloudfunctions.admin", "roles/artifactregistry.reader"] : {
        key    = "${user.email}-${role}"
        member = "user:${user.email}"
        role   = role
      }
    ] if user.deploy
  ])

  user_all_roles = concat(local.user_base_roles, local.user_deploy_roles)
}

resource "google_project_iam_member" "user" {
  for_each = { for binding in local.user_all_roles : binding.key => binding }
  project  = var.project
  role     = each.value.role
  member   = each.value.member
}

# ---------------------------------------------------------------------------
# CI Service Account (auto-determined roles)
# ---------------------------------------------------------------------------

resource "google_service_account" "ci" {
  count        = var.ci_service_account != null ? 1 : 0
  project      = var.project
  account_id   = var.ci_service_account.account_id
  display_name = var.ci_service_account.display_name
}

locals {
  ci_role_bindings = var.ci_service_account != null ? [
    for role in var.ci_service_account.roles : {
      key  = "${var.ci_service_account.account_id}-${role}"
      role = role
    }
  ] : []
}

resource "google_project_iam_member" "ci_role" {
  for_each = { for binding in local.ci_role_bindings : binding.key => binding }
  project  = var.project
  role     = each.value.role
  member   = "serviceAccount:${google_service_account.ci[0].email}"
}

# ---------------------------------------------------------------------------
# CI SA WIF binding (optional)
#
# 外部 CI (GitHub Actions / Terraform Cloud / GitLab CI 等) から CI SA を
# OIDC + Workload Identity Federation で impersonate する場合に使う。
# project-bootstrap が用意した WIF Pool を参照し、その上の attribute-based
# principalSet を `roles/iam.workloadIdentityUser` で bind する。
#
# `wif = null` (default) なら binding は作らない。
# principals[].attribute は WIF Provider の attribute mapping で公開されている
# 名前 (例: github=`repository`, tfc=`terraform_workspace`)。
# ---------------------------------------------------------------------------

locals {
  # for_each キーは "{attribute}/{value}" で安定化。
  # 同一 (attribute, value) が複数指定されても自動的に 1 binding に集約される。
  ci_wif_principals = (
    var.ci_service_account != null && try(var.ci_service_account.wif, null) != null
    ? {
      for p in var.ci_service_account.wif.principals :
      "${p.attribute}/${p.value}" => p
    }
    : {}
  )
}

resource "google_service_account_iam_member" "ci_wif" {
  for_each           = local.ci_wif_principals
  service_account_id = google_service_account.ci[0].name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${var.ci_service_account.wif.pool_resource_name}/attribute.${each.value.attribute}/${each.value.value}"
}

# ---------------------------------------------------------------------------
# Service Accounts (manual)
# ---------------------------------------------------------------------------

resource "google_service_account" "this" {
  for_each     = { for sa in var.service_accounts : sa.account_id => sa }
  project      = var.project
  account_id   = each.value.account_id
  display_name = each.value.display_name != "" ? each.value.display_name : each.value.account_id
}

locals {
  sa_computed_roles = {
    for sa in var.service_accounts : sa.account_id => distinct(
      sa.type == "deploy" ? concat(
        ["roles/runtimeconfig.admin"],
        try(sa.args.hosting, false) ? ["roles/firebasehosting.admin"] : [],
        try(sa.args.functions, false) ? ["roles/cloudfunctions.admin", "roles/iam.serviceAccountUser", "roles/artifactregistry.admin"] : [],
        try(sa.args.firestore, false) ? ["roles/datastore.indexAdmin", "roles/firebaserules.admin"] : [],
        try(sa.args.storage, false) ? ["roles/firebasestorage.viewer", "roles/storage.objectAdmin", "roles/storage.admin"] : [],
        try(sa.args.scheduler, false) ? ["roles/cloudscheduler.admin"] : [],
        try(sa.args.tasks, false) ? ["roles/cloudtasks.queueAdmin"] : [],
        try(sa.args.blocking, false) ? ["roles/firebaseauth.admin"] : [],
        sa.roles,
      ) : sa.roles
    )
  }

  sa_role_bindings = flatten([
    for sa_id, roles in local.sa_computed_roles : [
      for role in roles : {
        key        = "${sa_id}-${role}"
        account_id = sa_id
        role       = role
      }
    ]
  ])
}

resource "google_project_iam_member" "service_account_role" {
  for_each = { for binding in local.sa_role_bindings : binding.key => binding }
  project  = var.project
  role     = each.value.role
  member   = "serviceAccount:${google_service_account.this[each.value.account_id].email}"
}
