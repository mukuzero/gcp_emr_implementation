variables {
  project_id  = "test-project"
  db_password = "test-password"
  region      = "us-central1"
}

run "verify_cost_controls" {
  command = plan

  assert {
    condition     = google_sql_database_instance.default.settings[0].tier == "db-f1-micro"
    error_message = "Database tier must be db-f1-micro for low-cost environment"
  }

  assert {
    condition     = google_sql_database_instance.default.settings[0].disk_type == "PD_HDD"
    error_message = "Disk type must be PD_HDD to save costs"
  }

  assert {
    condition     = google_sql_database_instance.default.settings[0].availability_type == "ZONAL"
    error_message = "Availability type must be ZONAL to save costs"
  }
}

run "verify_deletion_protection" {
  command = plan

  assert {
    condition     = google_sql_database_instance.default.deletion_protection == false
    error_message = "Deletion protection should be disabled for dev/test environments"
  }
}
