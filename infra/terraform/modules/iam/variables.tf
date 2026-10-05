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

variable "secrets_arns" {
  description = "List of Secrets Manager secret ARNs the execution role injects into containers"
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}
