variable "project_id" {
  description = "The ID of the GCP project"
  type        = string
}

variable "region" {
  description = "The region to deploy resources in"
  type        = string
  default     = "us-central1"
}

variable "db_password" {
  description = "The password for the database user"
  type        = string
  sensitive   = true
}
