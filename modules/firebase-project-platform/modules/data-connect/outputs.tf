output "services" {
  description = "Map of Data Connect services, keyed by service_id."
  value = {
    for sid, mod in google_firebase_data_connect_service.this : sid => {
      resource_name = mod.name
      location      = mod.location
    }
  }
}

output "cloud_sql_instances" {
  description = "Map of Cloud SQL instances (deduplicated), keyed by instance_id."
  value = {
    for iid, mod in google_sql_database_instance.this : iid => {
      name             = mod.name
      connection_name  = mod.connection_name
      region           = mod.region
      database_version = mod.database_version
    }
  }
}

output "cloud_sql_databases" {
  description = "Map of Cloud SQL databases, keyed by '{instance_id}/{database}'."
  value = {
    for key, mod in google_sql_database.this : key => {
      instance = mod.instance
      name     = mod.name
    }
  }
}
