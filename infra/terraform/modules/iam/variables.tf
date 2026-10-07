variable "project" {
  description = "Project name used for resource naming and tagging"
  type        = string
}

variable "environment" {
  description = "Deployment environment (dev, staging, prod)"
  type        = string
}

variable "csv_bucket_arn" {
  description = "ARN of the S3 CSV uploads bucket"
  type        = string
}

variable "ecr_repository_arn" {
  description = "ARN of the ECR repository the execution role pulls the application image from"
  type        = string

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:ecr:[a-z0-9-]+:[0-9]{12}:repository/.+$", var.ecr_repository_arn))
    error_message = "ecr_repository_arn must be an ECR repository ARN."
  }
}

variable "secrets_arns" {
  description = "List of Secrets Manager secret ARNs the execution role injects into containers"
  type        = list(string)

  validation {
    condition     = length(var.secrets_arns) > 0 && alltrue([for arn in var.secrets_arns : can(regex("^arn:aws[a-z-]*:secretsmanager:[a-z0-9-]+:[0-9]{12}:secret:[A-Za-z0-9/_+=.@!-]+$", arn))])
    error_message = "secrets_arns must list at least one Secrets Manager secret ARN; wildcards and other services are rejected."
  }
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}
