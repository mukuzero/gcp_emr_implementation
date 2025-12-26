variable "project_id" {
  description = "The ID of the GCP project"
  type        = string
}

variable "region" {
  description = "The region to deploy resources in"
  type        = string
}

variable "db_password" {
  description = "The password for the database user"
  type        = string
  sensitive   = true
}

variable "db_name" {
  description = "The name of the database to create"
  type        = string
}

variable "db_user" {
  description = "The name of the database user to create"
  type        = string
}

variable "vpc_network_name" {
  description = "The name of the VPC network"
  type        = string
  default     = "dataproc-sql-network"
}

variable "subnetwork_name" {
  description = "The name of the subnetwork"
  type        = string
  default     = "dataproc-sql-subnet"
}

variable "subnet_cidr" {
  description = "The IP CIDR range for the subnetwork"
  type        = string
  default     = "10.0.0.0/16"
}

variable "private_ip_name" {
  description = "The name of the private IP address resource"
  type        = string
  default     = "private-ip-address"
}

variable "db_instance_prefix" {
  description = "The prefix for the Cloud SQL instance name"
  type        = string
  default     = "low-tier-db-instance"
}

variable "dataproc_cluster_name" {
  description = "The name of the Dataproc cluster"
  type        = string
  default     = "low-tier-cluster"
}

variable "firewall_rule_name" {
  description = "The name of the firewall rule"
  type        = string
  default     = "allow-internal-traffic"
}
variable "cloud_run_function_name" {
  description = "The name of the Cloud Run Function"
  type        = string
  default     = "data-loader-function"
}

variable "script_source_bucket_name" {
  description = "The name of the GCS bucket for script source code"
  type        = string
  default     = "script-source-bucket"
}
