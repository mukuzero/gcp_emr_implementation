output "db_instance_name" {
  description = "The name of the Cloud SQL instance"
  value       = google_sql_database_instance.default.name
}

output "db_connection_name" {
  description = "The connection name of the Cloud SQL instance"
  value       = google_sql_database_instance.default.connection_name
}
