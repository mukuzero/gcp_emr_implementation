output "db_instance_name" {
  description = "The name of the Cloud SQL instance"
  value       = google_sql_database_instance.default.name
}

output "db_connection_name" {
  description = "The connection name of the Cloud SQL instance"
  value       = google_sql_database_instance.default.connection_name
}

output "function_uri" {
  description = "The URI of the Cloud Run Function"
  value       = google_cloudfunctions2_function.data_loader.service_config[0].uri
}
