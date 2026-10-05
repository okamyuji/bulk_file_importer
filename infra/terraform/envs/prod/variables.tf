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

  validation {
    condition     = can(regex(local.ecr_image_uri_pattern, var.ecr_image_uri))
    error_message = "ecr_image_uri must be a private ECR image URI with a tag or sha256 digest (<account>.dkr.ecr.<region>.amazonaws.com/<repository>:<tag>)."
  }
}

variable "certificate_arn" {
  description = "ARN of the ACM certificate for HTTPS (required in prod; an empty value would serve plain HTTP)"
  type        = string

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:acm:[a-z0-9-]+:[0-9]{12}:certificate/.+$", var.certificate_arn))
    error_message = "certificate_arn must be an ACM certificate ARN."
  }
}

variable "rails_master_key" {
  description = "Rails production credentials key (the value of config/credentials/production.key)"
  type        = string
  sensitive   = true
  ephemeral   = true
}

variable "frontend_origin" {
  description = "Comma-separated origins allowed by CORS (e.g. https://app.example.com)"
  type        = string

  validation {
    condition     = trimspace(var.frontend_origin) != ""
    error_message = "frontend_origin must not be empty."
  }
}
