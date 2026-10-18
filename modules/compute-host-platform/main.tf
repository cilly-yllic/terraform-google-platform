/**
 * compute host（VM を置くプロジェクト）の基盤。
 *
 * Firebase のプロジェクトとは別のプロジェクトに、VM 用のネットワーク（カスタムモードの VPC・サブネット・
 * ファイアウォール・Cloud Router と Cloud NAT）と、最小権限の IAM（SA・SA を対象にした IAM・カスタムロールと
 * IAM の条件・別のプロジェクトの SA への付与）を作る。VM そのものは作らない（利用側のアプリが実行時に作る）。
 * プロジェクトは project-bootstrap で作る。
 *
 * Usage:
 *
 * ```tf
 * module "compute_host" {
 *   source  = "cilly-yllic/platform/google//modules/compute-host-platform"
 *   # version = "x.y.z"
 *
 *   project_id = "example-host-dev-001"
 *   region     = "asia-northeast1"
 *
 *   network = {
 *     name    = "vm"
 *     subnets = [{ name = "vm-asia-northeast1", cidr = "10.10.0.0/20" }]
 *   }
 *   firewall_rules = [
 *     { name = "deny-internal-egress", direction = "EGRESS", action = "deny", priority = 900,
 *       ranges = ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"] },
 *   ]
 *   cloud_nat = { router_name = "vm-router", nat_name = "vm-nat" }
 *
 *   service_accounts = [{ account_id = "vm-runtime" }]
 *   custom_roles = [{
 *     role_id     = "vmManager"
 *     title       = "VM manager"
 *     permissions = ["compute.instances.create", "compute.instances.start", "compute.instances.stop"]
 *   }]
 *   iam_bindings = [
 *     { role = "custom:vmManager", members = ["serviceAccount:manager@other-project.iam.gserviceaccount.com"] },
 *   ]
 *   service_account_iam = [
 *     { service_account = "vm-runtime", role = "roles/iam.serviceAccountUser",
 *       members = ["serviceAccount:manager@other-project.iam.gserviceaccount.com"] },
 *   ]
 * }
 * ```
 */

locals {
  base_apis = [
    "compute.googleapis.com",
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
  ]
  all_apis = distinct(concat(local.base_apis, var.apis))

  sa_ids = [for sa in var.service_accounts : sa.account_id]

  # "sa:<account_id>" をこのモジュールの SA のメンバーにする
  resolve_member = {
    for id in local.sa_ids : "sa:${id}" => "serviceAccount:${google_service_account.this[id].email}"
  }

  subnets = var.network == null ? {} : {
    for subnet in var.network.subnets : subnet.name => merge(subnet, {
      region = coalesce(subnet.region, var.region)
    })
  }

  firewall_rules = { for rule in var.firewall_rules : rule.name => rule }

  # IAM の付与を 1 件ずつにする（キーは入力から決まる文字列。値の role・member は作ってから決まってよい）
  project_bindings = merge([
    for index, binding in var.iam_bindings : {
      for member in binding.members : "${index}|${binding.role}|${member}" => {
        role      = binding.role
        member    = member
        condition = binding.condition
      }
    }
  ]...)

  sa_project_roles = merge([
    for sa in var.service_accounts : {
      for role in sa.roles : "${sa.account_id}|${role}" => { account_id = sa.account_id, role = role }
    }
  ]...)

  sa_bindings = merge([
    for index, binding in var.service_account_iam : {
      for member in binding.members : "${index}|${binding.service_account}|${binding.role}|${member}" => {
        service_account = binding.service_account
        role            = binding.role
        member          = member
      }
    }
  ]...)

  custom_role_ids = [for role in var.custom_roles : role.role_id]
}

# ---------------------------------------------------------------------------
# API
# ---------------------------------------------------------------------------

resource "google_project_service" "this" {
  for_each                   = toset(local.all_apis)
  project                    = var.project_id
  service                    = each.value
  disable_on_destroy         = false
  disable_dependent_services = true
}

# API を有効にした直後は、ほかの資源の作成が失敗することがある（伝播待ち）
resource "time_sleep" "api_propagation" {
  create_duration = var.api_propagation_wait

  # API のセットが変わった時だけ待ち直す（毎 apply で待たせない）
  triggers = {
    apis = join(",", sort(local.all_apis))
  }

  depends_on = [google_project_service.this]
}

# ---------------------------------------------------------------------------
# ネットワーク
# ---------------------------------------------------------------------------

resource "google_compute_network" "this" {
  count                   = var.network == null ? 0 : 1
  project                 = var.project_id
  name                    = var.network.name
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"

  depends_on = [time_sleep.api_propagation]
}

resource "google_compute_subnetwork" "this" {
  for_each                 = local.subnets
  project                  = var.project_id
  name                     = each.value.name
  region                   = each.value.region
  network                  = google_compute_network.this[0].id
  ip_cidr_range            = each.value.cidr
  private_ip_google_access = each.value.private_google_access

  dynamic "log_config" {
    for_each = each.value.flow_logs ? [1] : []
    content {
      aggregation_interval = "INTERVAL_5_SEC"
      flow_sampling        = 0.5
      metadata             = "INCLUDE_ALL_METADATA"
    }
  }
}

resource "google_compute_firewall" "this" {
  for_each    = local.firewall_rules
  project     = var.project_id
  name        = each.value.name
  network     = google_compute_network.this[0].id
  direction   = each.value.direction
  priority    = each.value.priority
  description = each.value.description

  source_ranges      = each.value.direction == "INGRESS" ? each.value.ranges : null
  destination_ranges = each.value.direction == "EGRESS" ? each.value.ranges : null

  target_tags = length(each.value.target_tags) > 0 ? each.value.target_tags : null
  target_service_accounts = length(each.value.target_service_accounts) > 0 ? [
    for value in each.value.target_service_accounts :
    strcontains(value, "@") ? value : google_service_account.this[value].email
  ] : null

  dynamic "allow" {
    for_each = each.value.action == "allow" ? each.value.protocols : []
    content {
      protocol = allow.value.protocol
      ports    = length(allow.value.ports) > 0 ? allow.value.ports : null
    }
  }

  dynamic "deny" {
    for_each = each.value.action == "deny" ? each.value.protocols : []
    content {
      protocol = deny.value.protocol
      ports    = length(deny.value.ports) > 0 ? deny.value.ports : null
    }
  }

  dynamic "log_config" {
    for_each = each.value.log ? [1] : []
    content {
      metadata = "INCLUDE_ALL_METADATA"
    }
  }
}

resource "google_compute_router" "this" {
  count   = var.cloud_nat == null ? 0 : 1
  project = var.project_id
  name    = var.cloud_nat.router_name
  region  = coalesce(var.cloud_nat.region, var.region)
  network = google_compute_network.this[0].id
}

resource "google_compute_router_nat" "this" {
  count                              = var.cloud_nat == null ? 0 : 1
  project                            = var.project_id
  name                               = var.cloud_nat.nat_name
  router                             = google_compute_router.this[0].name
  region                             = google_compute_router.this[0].region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
  min_ports_per_vm                   = var.cloud_nat.min_ports_per_vm

  log_config {
    enable = var.cloud_nat.log_filter != "NONE"
    filter = var.cloud_nat.log_filter == "NONE" ? "ERRORS_ONLY" : var.cloud_nat.log_filter
  }
}

# ---------------------------------------------------------------------------
# IAM
# ---------------------------------------------------------------------------

resource "google_service_account" "this" {
  for_each     = toset(local.sa_ids)
  project      = var.project_id
  account_id   = each.value
  display_name = coalesce([for sa in var.service_accounts : sa.display_name if sa.account_id == each.value][0], each.value)

  depends_on = [time_sleep.api_propagation]
}

resource "google_project_iam_custom_role" "this" {
  for_each    = { for role in var.custom_roles : role.role_id => role }
  project     = var.project_id
  role_id     = each.value.role_id
  title       = each.value.title
  description = each.value.description
  permissions = each.value.permissions
  stage       = each.value.stage

  depends_on = [time_sleep.api_propagation]
}

resource "google_project_iam_member" "service_account_roles" {
  for_each = local.sa_project_roles
  project  = var.project_id
  role = (
    startswith(each.value.role, "custom:")
    ? google_project_iam_custom_role.this[trimprefix(each.value.role, "custom:")].name
    : each.value.role
  )
  member = "serviceAccount:${google_service_account.this[each.value.account_id].email}"
}

resource "google_project_iam_member" "bindings" {
  for_each = local.project_bindings
  project  = var.project_id
  role = (
    startswith(each.value.role, "custom:")
    ? google_project_iam_custom_role.this[trimprefix(each.value.role, "custom:")].name
    : each.value.role
  )
  member = lookup(local.resolve_member, each.value.member, each.value.member)

  dynamic "condition" {
    for_each = each.value.condition == null ? [] : [each.value.condition]
    content {
      title       = condition.value.title
      expression  = condition.value.expression
      description = condition.value.description
    }
  }
}

resource "google_service_account_iam_member" "this" {
  for_each           = local.sa_bindings
  service_account_id = google_service_account.this[each.value.service_account].name
  role               = each.value.role
  member             = lookup(local.resolve_member, each.value.member, each.value.member)
}
