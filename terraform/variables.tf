variable "aws_region" {
  description = "AWS region to deploy resources into"
  type        = string
  default     = "eu-central-1"
}

variable "project_name" {
  description = "Name used to prefix and tag all resources in this project"
  type        = string
  default     = "lambda-api-project"
}

variable "environment" {
  description = "Deployment environment (e.g. dev, staging, prod)"
  type        = string
  default     = "dev"
}
