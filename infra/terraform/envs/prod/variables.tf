variable "project" {
  description = "Project name used for resource naming and tagging"
  type        = string
}

variable "environment" {
  description = "Deployment environment"
  type        = string
  default     = "prod"
}

variable "region" {
  description = "AWS region to deploy into"
  type        = string
}

variable "db_name" {
  description = "Name of the Aurora MySQL database"
  type        = string
  default     = "bulk_file_importer_prod"
}

variable "db_username" {
  description = "Master username for the Aurora MySQL cluster"
  type        = string
  default     = "admin"
}

variable "ecr_image_uri" {
  description = "Full ECR image URI including tag for the Rails application"
  type        = string
}

variable "certificate_arn" {
  description = "ARN of the ACM certificate for HTTPS"
  type        = string
  default     = ""
}
