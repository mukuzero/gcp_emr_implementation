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
