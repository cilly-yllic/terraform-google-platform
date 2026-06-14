variable "project" {
  description = "GCP project ID."
  type        = string
}

variable "default_location" {
  description = "Fallback location used when a service entry omits location."
  type        = string
}

variable "services" {
  description = <<-EOT
    Data Connect services (1 project に複数 service)。
    各 service は Cloud SQL Instance + Database に link する。

      service_id           = 必須 (project-unique)
      location             = optional (省略時 var.default_location)
      cloud_sql            = 必須 (Data Connect は Cloud SQL backend が必要)
        instance_id        = 必須 (Cloud SQL Instance name、複数 service が同 instance_id を
                             指せば自動 dedup されて 1 instance に集約される)
        database           = 必須 (instance 内の logical database 名)
        tier               = optional (default "db-f1-micro"、同 instance_id を共有する
                             entries 間で一致が必要、不一致は precondition error)
        database_version   = optional (default "POSTGRES_15"、同様に instance 一貫性必須)
        deletion_protection = optional (default false、同様に instance 一貫性必須)
        location           = optional (default はその service の location を採用、
                             同 instance_id 内で一貫性必須)
  EOT
  type = list(object({
    service_id = string
    location   = optional(string, "")
    cloud_sql = object({
      instance_id         = string
      database            = string
      tier                = optional(string, "db-f1-micro")
      database_version    = optional(string, "POSTGRES_15")
      deletion_protection = optional(bool, false)
      location            = optional(string, "")
    })
  }))
  default = []
}
