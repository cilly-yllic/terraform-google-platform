output "network_id" {
  description = "VPC の ID（network を指定しなければ null）"
  value       = try(google_compute_network.this[0].id, null)
}

output "network_self_link" {
  description = "VPC の self link（network を指定しなければ null）"
  value       = try(google_compute_network.this[0].self_link, null)
}

output "subnets" {
  description = "サブネットの名前 → { id, self_link, region, cidr }"
  value = {
    for name, subnet in google_compute_subnetwork.this : name => {
      id        = subnet.id
      self_link = subnet.self_link
      region    = subnet.region
      cidr      = subnet.ip_cidr_range
    }
  }
}

output "service_accounts" {
  description = "SA の account_id → { email, member }"
  value = {
    for id, sa in google_service_account.this : id => {
      email  = sa.email
      member = "serviceAccount:${sa.email}"
    }
  }
}

output "custom_roles" {
  description = "カスタムロールの role_id → ロールの名前（projects/<project>/roles/<role_id>）"
  value       = { for id, role in google_project_iam_custom_role.this : id => role.name }
}

output "cloud_nat" {
  description = "Cloud Router と Cloud NAT の名前（cloud_nat を指定しなければ null）"
  value = var.cloud_nat == null ? null : {
    router = google_compute_router.this[0].name
    nat    = google_compute_router_nat.this[0].name
    region = google_compute_router.this[0].region
  }
}
