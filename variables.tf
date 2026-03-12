# HiHo Worker - GCP Terraform Variables (DEV)

variable "project_id" {
  description = "GCP Project ID where resources will be created"
  type        = string
}

variable "region" {
  description = "GCP region for resources"
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "GCP zone for the VM"
  type        = string
  default     = "us-central1-a"
}

variable "admin_email" {
  description = "Google Workspace admin email for domain-wide delegation"
  type        = string
}

variable "api_token" {
  description = "HiHo API token for authentication"
  type        = string
  sensitive   = true
}

variable "machine_type" {
  description = "GCP machine type for the VM"
  type        = string
  default     = "e2-medium"
}

variable "registry_url" {
  description = "Container registry URL"
  type        = string
  default     = "git.hihoworks.com/data-connector/hiho-worker-dev"
}

variable "image_tag" {
  description = "Container image tag"
  type        = string
  default     = "latest"
}
