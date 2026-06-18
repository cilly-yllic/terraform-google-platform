# ---------------------------------------------------------------------------
# Data Connect - services / Cloud SQL instances / Cloud SQL databases の dedup
#
# 設計:
#   - services は service_id をキーに for_each (1 service = 1 GraphQL endpoint)
#   - Cloud SQL Instance は instance_id をキーに for_each で dedup
#     (複数 service が同 instance_id を指せば 1 instance に集約してコスト削減)
#   - Cloud SQL Database は (instance_id, database) をキーに for_each
#     (1 instance 内で複数 database 可、ただし同 service_id が複数 db を作る形式は無し:
#      1 service = 1 database という Firebase Data Connect の仕様に従う)
#
# 一貫性 validation (precondition):
#   - 同 instance_id を持つ entries の tier / database_version /
#     deletion_protection / location が全て同じであること (Cloud SQL Instance は
#     1 つの設定で 1 つの region を持つため)
# ---------------------------------------------------------------------------

locals {
  # 各 service の正規化された entry (location / cloud_sql.location を解決)
  services_list = [
    for s in var.services : {
      service_id          = s.service_id
      location            = s.location != "" ? s.location : var.default_location
      cs_instance_id      = s.cloud_sql.instance_id
      cs_database         = s.cloud_sql.database
      cs_tier             = s.cloud_sql.tier
      cs_database_version = s.cloud_sql.database_version
      cs_deletion_protect = s.cloud_sql.deletion_protection
      cs_location = (
        s.cloud_sql.location != "" ? s.cloud_sql.location :
        s.location != "" ? s.location : var.default_location
      )
    }
  ]

  services_map = { for s in local.services_list : s.service_id => s }

  # Cloud SQL Instance を instance_id でユニーク化 (最初の出現を採用)。
  # 後段で同 instance_id の全 entries が同 properties を持っていることを precondition で check。
  cloud_sql_instances_map = {
    for s in local.services_list : s.cs_instance_id => {
      tier                = s.cs_tier
      database_version    = s.cs_database_version
      deletion_protection = s.cs_deletion_protect
      location            = s.cs_location
    }...
  }

  # 上の map で each instance_id の最初の entry を採用 (canonical properties)
  cloud_sql_instances_canonical = {
    for instance_id, group in local.cloud_sql_instances_map : instance_id => group[0]
  }

  # Cloud SQL Database を (instance_id + database) でユニーク化。
  cloud_sql_databases_map = {
    for s in local.services_list : "${s.cs_instance_id}/${s.cs_database}" => {
      instance_id = s.cs_instance_id
      database    = s.cs_database
    }
  }
}

# ---------------------------------------------------------------------------
# 一貫性 validation: 同 instance_id の properties が揃っているか
# ---------------------------------------------------------------------------

resource "terraform_data" "validate_cloud_sql_instance_consistency" {
  for_each = local.cloud_sql_instances_map
  input    = each.key

  lifecycle {
    precondition {
      condition     = length(distinct([for e in each.value : e.tier])) <= 1
      error_message = "data_connect: Cloud SQL instance_id '${each.key}' has inconsistent tier across services. All services sharing this instance must use the same tier."
    }
    precondition {
      condition     = length(distinct([for e in each.value : e.database_version])) <= 1
      error_message = "data_connect: Cloud SQL instance_id '${each.key}' has inconsistent database_version across services. All services sharing this instance must use the same database_version."
    }
    precondition {
      condition     = length(distinct([for e in each.value : e.deletion_protection])) <= 1
      error_message = "data_connect: Cloud SQL instance_id '${each.key}' has inconsistent deletion_protection across services."
    }
    precondition {
      condition     = length(distinct([for e in each.value : e.location])) <= 1
      error_message = "data_connect: Cloud SQL instance_id '${each.key}' has inconsistent location (region) across services. Cloud SQL Instance has a single region."
    }
  }
}

# ---------------------------------------------------------------------------
# Cloud SQL Instances (deduplicated)
# ---------------------------------------------------------------------------

resource "google_sql_database_instance" "this" {
  for_each            = local.cloud_sql_instances_canonical
  project             = var.project
  name                = each.key
  region              = each.value.location
  database_version    = each.value.database_version
  deletion_protection = each.value.deletion_protection

  settings {
    tier              = each.value.tier
    edition           = "ENTERPRISE"
    availability_type = "ZONAL"

    # Firebase Data Connect は Cloud SQL への接続に IAM 認証を要求する。
    # このフラグが無いと firebase CLI が deploy 時にインスタンスを更新しようとし、
    # "settings are not compatible with Firebase SQL Connect" → instance update で
    # 409 (operation already in progress) になる。terraform 側で最初から有効化して
    # おくことで CLI による変更を不要にする (Postgres は cloudsql.iam_authentication=on)。
    database_flags {
      name  = "cloudsql.iam_authentication"
      value = "on"
    }

    backup_configuration {
      enabled = true
    }

    ip_configuration {
      ipv4_enabled = true
    }
  }

  depends_on = [terraform_data.validate_cloud_sql_instance_consistency]
}

# ---------------------------------------------------------------------------
# Cloud SQL Databases
# ---------------------------------------------------------------------------

resource "google_sql_database" "this" {
  for_each = local.cloud_sql_databases_map
  project  = var.project
  instance = google_sql_database_instance.this[each.value.instance_id].name
  name     = each.value.database
}

# ---------------------------------------------------------------------------
# Firebase Data Connect Services
# ---------------------------------------------------------------------------

resource "google_firebase_data_connect_service" "this" {
  for_each   = local.services_map
  provider   = google-beta
  project    = var.project
  location   = each.value.location
  service_id = each.value.service_id

  depends_on = [google_sql_database.this]
}
