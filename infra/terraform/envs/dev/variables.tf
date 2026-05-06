variable "project" {
  description = "Project name used for resource naming and tagging"
  type        = string
}

variable "environment" {
  description = "Deployment environment"
  type        = string
  default     = "dev"
}

variable "region" {
  description = "AWS region to deploy into"
  type        = string
}

variable "db_name" {
  description = "Name of the Aurora MySQL database"
  type        = string
  default     = "bulk_file_importer"
}

variable "db_username" {
  description = "Master username for the Aurora MySQL cluster"
  type        = string
  default     = "admin"
}

variable "rails_master_key" {
  description = "Rails master key (from config/master.key)"
  type        = string
  sensitive   = true
}
