
variable "region" {
  description = "Cluster region"
  default     = "ap-southeast-2"
}

variable "cluster_name" {
  type    = string
  default = "fhir-k8s-dev"
}
variable "vpc_name" {
  description = "Name of the VPC"
  type        = string
  default     = "fhir-k8s-dev-vpc"
}

variable "rds_name" {
  description = "The name of the RDS instance"
  type        = string
  default     = ""
}

variable "environment" {
  description = "Environment"
  type        = string
  default     = "dev"
}

variable "name" {
  description = "Name of the application"
  type        = string
  default     = "inferno"
}

variable "usesWrapper" {
  description = "Boolean to determine if the application is a wrapper of inferno or just the core inferno test kit"
  type        = bool
}

variable "snapshot_identifier" {
  type        = string
  description = "Optional snapshot identifier for restoring an RDS instance from a snapshot."
  default     = null
}

variable "postgres_instance_class" {
  type        = string
  description = "The instance class to use for the RDS instance"
  default     = "db.t4g.small"
}
