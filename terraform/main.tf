resource "google_sql_database_instance" "default" {
  name             = "low-tier-db-instance-${random_id.db_name_suffix.hex}"
  database_version = "POSTGRES_15"
  region           = var.region

  settings {
    # "db-f1-micro" is a shared-core machine type, suitable for low-tier/dev environments
    tier = "db-f1-micro"

    # Zonal availability is cheaper than Regional
    availability_type = "ZONAL"

    # Use HDD instead of SSD for lower cost
    disk_type = "PD_HDD"
    disk_size = 10 # Minimum size in GB

    ip_configuration {
      ipv4_enabled = true
    }
  }

  # For demonstration/dev purposes only. Set to true for production.
  deletion_protection = false
}

resource "random_id" "db_name_suffix" {
  byte_length = 4
}

resource "google_sql_database" "database" {
  name     = var.db_name
  instance = google_sql_database_instance.default.name
}

resource "google_sql_user" "users" {
  name     = var.db_user
  instance = google_sql_database_instance.default.name
  password = var.db_password
}
