# compute-host-platform の回帰テスト（mock provider のみ、認証不要）。
#   cd modules/compute-host-platform
#   terraform init -backend=false && terraform test

mock_provider "google" {
  mock_resource "google_service_account" {
    defaults = {
      email = "vm-runtime@test-project.iam.gserviceaccount.com"
      name  = "projects/test-project/serviceAccounts/vm-runtime@test-project.iam.gserviceaccount.com"
    }
  }
  mock_resource "google_project_iam_custom_role" {
    defaults = {
      name = "projects/test-project/roles/vmManager"
    }
  }
}
mock_provider "time" {}

variables {
  project_id           = "test-project"
  api_propagation_wait = "0s"
}

# 何も指定しなければ API だけを有効にし、ネットワーク・IAM は作らない
run "omitted_creates_only_apis" {
  command = plan

  assert {
    condition     = contains(keys(google_project_service.this), "compute.googleapis.com")
    error_message = "compute の API を有効にしていない"
  }
  assert {
    condition = (
      length(google_compute_network.this) == 0 &&
      length(google_compute_router_nat.this) == 0 &&
      length(google_service_account.this) == 0 &&
      length(google_project_iam_member.bindings) == 0
    )
    error_message = "未指定なのにネットワーク・IAM を作っている"
  }
}

run "network_firewall_nat" {
  command = apply

  variables {
    network = {
      name = "vm"
      subnets = [
        { name = "vm-a", cidr = "10.10.0.0/20" },
        { name = "vm-b", cidr = "10.20.0.0/20", region = "us-central1", private_google_access = false, flow_logs = true },
      ]
    }
    firewall_rules = [
      {
        name      = "deny-internal-egress"
        direction = "EGRESS"
        action    = "deny"
        priority  = 900
        ranges    = ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"]
      },
      {
        name                    = "allow-https-egress"
        direction               = "EGRESS"
        action                  = "allow"
        ranges                  = ["0.0.0.0/0"]
        protocols               = [{ protocol = "tcp", ports = ["443"] }]
        target_service_accounts = ["vm-runtime"]
      },
    ]
    cloud_nat        = { router_name = "vm-router", nat_name = "vm-nat" }
    service_accounts = [{ account_id = "vm-runtime" }]
  }

  assert {
    condition     = google_compute_network.this[0].auto_create_subnetworks == false
    error_message = "VPC がカスタムモードになっていない"
  }
  assert {
    condition = (
      google_compute_subnetwork.this["vm-a"].region == "asia-northeast1" &&
      google_compute_subnetwork.this["vm-a"].private_ip_google_access == true &&
      length(google_compute_subnetwork.this["vm-a"].log_config) == 0
    )
    error_message = "既定のサブネット（リージョン・Private Google Access・フローログ）が違う"
  }
  assert {
    condition = (
      google_compute_subnetwork.this["vm-b"].region == "us-central1" &&
      google_compute_subnetwork.this["vm-b"].private_ip_google_access == false &&
      length(google_compute_subnetwork.this["vm-b"].log_config) == 1
    )
    error_message = "サブネットの指定が反映されていない"
  }
  assert {
    condition = (
      google_compute_firewall.this["deny-internal-egress"].direction == "EGRESS" &&
      tolist(google_compute_firewall.this["deny-internal-egress"].destination_ranges) == tolist(["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"]) &&
      length(google_compute_firewall.this["deny-internal-egress"].deny) == 1 &&
      length(google_compute_firewall.this["deny-internal-egress"].allow) == 0 &&
      google_compute_firewall.this["deny-internal-egress"].priority == 900
    )
    error_message = "拒否のルールが違う"
  }
  assert {
    condition = (
      tolist(google_compute_firewall.this["allow-https-egress"].target_service_accounts) == tolist(["vm-runtime@test-project.iam.gserviceaccount.com"]) &&
      length(google_compute_firewall.this["allow-https-egress"].allow) == 1
    )
    error_message = "account_id を SA のメールにしていない、または許可のルールが違う"
  }
  assert {
    condition = (
      google_compute_router_nat.this[0].source_subnetwork_ip_ranges_to_nat == "ALL_SUBNETWORKS_ALL_IP_RANGES" &&
      google_compute_router_nat.this[0].min_ports_per_vm == 64 &&
      google_compute_router_nat.this[0].log_config[0].enable == true &&
      google_compute_router_nat.this[0].log_config[0].filter == "ERRORS_ONLY"
    )
    error_message = "Cloud NAT の既定（全サブネット・ポート・エラーだけのログ）が違う"
  }
}

run "nat_without_logs" {
  command = plan

  variables {
    network   = { name = "vm", subnets = [{ name = "vm-a", cidr = "10.10.0.0/20" }] }
    cloud_nat = { router_name = "vm-router", nat_name = "vm-nat", log_filter = "NONE" }
  }

  assert {
    condition     = google_compute_router_nat.this[0].log_config[0].enable == false
    error_message = "log_filter = NONE でもログを出している"
  }
}

run "iam_custom_roles_conditions_and_sa_scoped" {
  command = apply

  variables {
    service_accounts = [
      { account_id = "vm-runtime" },
      { account_id = "vm-reconciler", roles = ["roles/monitoring.viewer", "custom:vmManager"] },
    ]
    custom_roles = [{
      role_id     = "vmManager"
      title       = "VM manager"
      permissions = ["compute.instances.create", "compute.instances.stop"]
    }]
    iam_bindings = [
      {
        role    = "custom:vmManager"
        members = ["serviceAccount:manager@other-project.iam.gserviceaccount.com"]
        condition = {
          title      = "vm-prefix"
          expression = "resource.name.extract(\"/instances/{name}\").startsWith(\"vm-\")"
        }
      },
      { role = "roles/logging.viewer", members = ["sa:vm-reconciler", "group:ops@example.com"] },
    ]
    service_account_iam = [{
      service_account = "vm-runtime"
      role            = "roles/iam.serviceAccountUser"
      members         = ["serviceAccount:manager@other-project.iam.gserviceaccount.com"]
    }]
  }

  assert {
    condition     = google_project_iam_custom_role.this["vmManager"].stage == "GA"
    error_message = "カスタムロールの既定の stage が違う"
  }
  assert {
    condition = (
      google_project_iam_member.bindings["0|custom:vmManager|serviceAccount:manager@other-project.iam.gserviceaccount.com"].role == "projects/test-project/roles/vmManager" &&
      google_project_iam_member.bindings["0|custom:vmManager|serviceAccount:manager@other-project.iam.gserviceaccount.com"].condition[0].title == "vm-prefix"
    )
    error_message = "custom:<role_id> をロールの名前にしていない、または条件が付いていない"
  }
  assert {
    condition = (
      google_project_iam_member.bindings["1|roles/logging.viewer|sa:vm-reconciler"].member == "serviceAccount:vm-runtime@test-project.iam.gserviceaccount.com" &&
      google_project_iam_member.bindings["1|roles/logging.viewer|group:ops@example.com"].member == "group:ops@example.com" &&
      length(google_project_iam_member.bindings["1|roles/logging.viewer|group:ops@example.com"].condition) == 0
    )
    error_message = "sa:<account_id> をこのモジュールの SA にしていない、またはほかのメンバーをそのまま渡していない"
  }
  assert {
    condition = (
      google_project_iam_member.service_account_roles["vm-reconciler|custom:vmManager"].role == "projects/test-project/roles/vmManager" &&
      google_project_iam_member.service_account_roles["vm-reconciler|roles/monitoring.viewer"].role == "roles/monitoring.viewer"
    )
    error_message = "SA のプロジェクトの role が違う"
  }
  assert {
    condition = (
      google_service_account_iam_member.this["0|vm-runtime|roles/iam.serviceAccountUser|serviceAccount:manager@other-project.iam.gserviceaccount.com"].service_account_id == "projects/test-project/serviceAccounts/vm-runtime@test-project.iam.gserviceaccount.com"
    )
    error_message = "SA を対象にした IAM の対象が違う"
  }
}

run "rejects_unknown_custom_role" {
  command = plan
  variables {
    iam_bindings = [{ role = "custom:missing", members = ["user:someone@example.com"] }]
  }
  expect_failures = [var.iam_bindings]
}

run "rejects_unknown_sa_member" {
  command = plan
  variables {
    iam_bindings = [{ role = "roles/viewer", members = ["sa:missing"] }]
  }
  expect_failures = [var.iam_bindings]
}

run "rejects_sa_iam_for_unknown_target" {
  command = plan
  variables {
    service_account_iam = [{ service_account = "missing", role = "roles/iam.serviceAccountUser", members = ["user:someone@example.com"] }]
  }
  expect_failures = [var.service_account_iam]
}

run "rejects_firewall_without_network" {
  command = plan
  variables {
    firewall_rules = [{ name = "x", direction = "EGRESS", action = "deny", ranges = ["10.0.0.0/8"] }]
  }
  expect_failures = [var.firewall_rules]
}

run "rejects_nat_without_network" {
  command = plan
  variables {
    cloud_nat = { router_name = "r", nat_name = "n" }
  }
  expect_failures = [var.cloud_nat]
}

run "rejects_invalid_firewall_direction" {
  command = plan
  variables {
    network        = { name = "vm", subnets = [{ name = "vm-a", cidr = "10.10.0.0/20" }] }
    firewall_rules = [{ name = "x", direction = "OUT", action = "deny", ranges = ["10.0.0.0/8"] }]
  }
  expect_failures = [var.firewall_rules]
}

run "rejects_both_target_kinds" {
  command = plan
  variables {
    network          = { name = "vm", subnets = [{ name = "vm-a", cidr = "10.10.0.0/20" }] }
    service_accounts = [{ account_id = "vm-runtime" }]
    firewall_rules = [{
      name        = "x", direction = "EGRESS", action = "deny", ranges = ["10.0.0.0/8"],
      target_tags = ["vm"], target_service_accounts = ["vm-runtime"]
    }]
  }
  expect_failures = [var.firewall_rules]
}

run "rejects_unknown_nat_log_filter" {
  command = plan
  variables {
    network   = { name = "vm", subnets = [{ name = "vm-a", cidr = "10.10.0.0/20" }] }
    cloud_nat = { router_name = "r", nat_name = "n", log_filter = "VERBOSE" }
  }
  expect_failures = [var.cloud_nat]
}

run "rejects_duplicate_service_accounts" {
  command = plan
  variables {
    service_accounts = [{ account_id = "vm-runtime" }, { account_id = "vm-runtime" }]
  }
  expect_failures = [var.service_accounts]
}
