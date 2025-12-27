# Network
resource "google_compute_network" "vpc_network" {
  name                    = var.vpc_network_name
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "subnetwork" {
  name          = var.subnetwork_name
  ip_cidr_range = var.subnet_cidr
  region        = var.region
  network       = google_compute_network.vpc_network.id
}

# Private Service Access for Cloud SQL
resource "google_compute_global_address" "private_ip_address" {
  name          = var.private_ip_name
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = google_compute_network.vpc_network.id
}

resource "google_service_networking_connection" "private_vpc_connection" {
  network                 = google_compute_network.vpc_network.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_ip_address.name]
}

# Cloud SQL
resource "google_sql_database_instance" "default" {
  name             = "${var.db_instance_prefix}-${random_id.db_name_suffix.hex}"
  database_version = "POSTGRES_15"
  region           = var.region

  depends_on = [google_service_networking_connection.private_vpc_connection]

  settings {
    # "db-f1-micro" is a shared-core machine type, suitable for low-tier/dev environments
    tier = "db-f1-micro"

    # Zonal availability is cheaper than Regional
    availability_type = "ZONAL"

    # Use HDD instead of SSD for lower cost
    disk_type = "PD_HDD"
    disk_size = 10 # Minimum size in GB

    ip_configuration {
      ipv4_enabled    = false # Disable public IP
      private_network = google_compute_network.vpc_network.id
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

# Dataproc Cluster
resource "google_dataproc_cluster" "mycluster" {
  name   = var.dataproc_cluster_name
  region = var.region

  cluster_config {
    # Keep it low tier: Single Node Cluster
    master_config {
      num_instances = 1
      machine_type  = "e2-standard-2" # Cost effective
      disk_config {
        boot_disk_type    = "pd-standard"
        boot_disk_size_gb = 30
      }
    }

    worker_config {
      num_instances = 0
    }

    software_config {
      image_version = "2.1-debian11"
      override_properties = {
        "dataproc:dataproc.allow.zero.workers" = "true"
      }
    }

    gce_cluster_config {
      subnetwork = google_compute_subnetwork.subnetwork.id
      tags       = ["dataproc-node"]
      # Scopes needed for Dataproc and Cloud SQL access
      service_account_scopes = [
        "https://www.googleapis.com/auth/cloud-platform"
      ]
    }
  }
}

# Firewall Rule to allow internal communication
resource "google_compute_firewall" "allow_internal" {
  name    = var.firewall_rule_name
  network = google_compute_network.vpc_network.name

  allow {
    protocol = "icmp"
  }

  allow {
    protocol = "tcp"
    ports    = ["0-65535"]
  }

  allow {
    protocol = "udp"
    ports    = ["0-65535"]
  }

  source_ranges = [var.subnet_cidr]
}

# Cloud Run Function for Data Loading

# Create a zip of the scripts directory
data "archive_file" "function_source" {
  type        = "zip"
  source_dir  = "../scripts/cloud_run"
  output_path = "${path.module}/function_source.zip"
  excludes    = ["__pycache__", "*.pyc"]
}

# Create a bucket for the function source code
resource "google_storage_bucket" "function_bucket" {
  name     = "${var.script_source_bucket_name}-${random_id.db_name_suffix.hex}"
  location = var.region
}

# Upload the zip to the bucket
resource "google_storage_bucket_object" "function_archive" {
  name   = "function_source.${data.archive_file.function_source.output_md5}.zip"
  bucket = google_storage_bucket.function_bucket.name
  source = data.archive_file.function_source.output_path
}

# Create the Cloud Run Function (Gen 2)
resource "google_cloudfunctions2_function" "data_loader" {
  name        = var.cloud_run_function_name
  location    = var.region
  description = "Cloud Run Function to load data into Cloud SQL"

  build_config {
    runtime     = "python311"
    entry_point = "main" # Entry point in cloud_run_loader.py
    source {
      storage_source {
        bucket = google_storage_bucket.function_bucket.name
        object = google_storage_bucket_object.function_archive.name
      }
    }
    environment_variables = {
      GOOGLE_FUNCTION_SOURCE = var.function_source_file
    }
  }

  service_config {
    max_instance_count = 1
    available_memory   = "4Gi"
    available_cpu      = "2"
    timeout_seconds    = 300

    # Connect to the VPC
    vpc_connector_egress_settings = "PRIVATE_RANGES_ONLY"

    # Direct VPC Egress (requires beta provider or specific config, using standard connector approach for stability if connector exists, 
    # but since we don't have a connector resource defined, we'll try Direct VPC Egress if supported by the provider version, 
    # OR we need to create a VPC connector. 
    # However, Gen 2 supports Direct VPC Egress. Let's try to use the network interfaces block if provider supports it, 
    # or just set the VPC connector if we had one.
    # Given the constraint "within the same vpc", and no existing connector, Direct VPC Egress is the modern way.
    # But Terraform provider support for Direct VPC Egress in `google_cloudfunctions2_function` might need specific syntax.
    # It is usually done via `vpc_connector` field pointing to a connector, OR `network_interfaces` block?
    # Actually, Gen 2 uses the underlying Cloud Run service.
    # Let's check the standard way to do Direct VPC Egress in Terraform for Gen 2.
    # It seems `vpc_connector` is still the primary way unless using `google_cloud_run_v2_service`.
    # BUT, `google_cloudfunctions2_function` wraps Cloud Run.
    # Let's try to use the `vpc_connector` field but since we don't have one, we might need to create one OR use the subnetwork directly?
    # Wait, Gen 2 supports Direct VPC Egress via `vpc_connector = null` and setting network/subnetwork?
    # No, for Direct VPC Egress, we typically need to configure the underlying service.
    # Let's stick to the simplest valid configuration. If Direct VPC Egress is tricky without a connector, 
    # I will create a VPC connector resource as well to be safe, OR try to link the subnetwork directly if I recall the syntax.
    # Re-reading docs (mental check): Direct VPC Egress uses `vpc_access` block in Cloud Run.
    # In `google_cloudfunctions2_function`, `service_config` has `vpc_connector`.
    # If I want Direct VPC Egress, I might need to use `google_cloud_run_v2_service` directly or check if `service_config` supports `network_interfaces`.
    # Let's look at `service_config` arguments. It has `vpc_connector` and `vpc_connector_egress_settings`.
    # It DOES NOT seem to have `network_interfaces` exposed directly in the high-level resource yet in all versions.
    # To avoid complexity/errors, I will create a `google_vpc_access_connector` resource as well, 
    # as that is the standard, robust way to ensure VPC access for Cloud Functions.

    # Wait, the user asked to use "correct variables within vpc defined".
    # I will create a VPC connector to ensure connectivity.
    vpc_connector = google_vpc_access_connector.connector.id

    environment_variables = {
      DB_HOST     = google_sql_database_instance.default.private_ip_address
      DB_NAME     = var.db_name
      DB_USER     = var.db_user
      DB_PASSWORD = var.db_password
    }
  }
}

# VPC Access Connector (Required for Cloud Function to access VPC)
resource "google_vpc_access_connector" "connector" {
  name          = "vpc-connector"
  region        = var.region
  network       = google_compute_network.vpc_network.name
  ip_cidr_range = "10.8.0.0/28" # /28 is the minimum required
}


