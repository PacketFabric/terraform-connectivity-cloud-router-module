variable "name" {}
variable "labels" {}
variable "cr_id" {}

variable "aws_cloud_router_connections" {
  default = null
}
variable "google_cloud_router_connections" {
  default = null
}
variable "azure_cloud_router_connections" {
  default = null
}

variable "aws_in_prefixes" {
  default = []
}
variable "google_in_prefixes" {
  default = []
}

variable "module_enabled" {
  description = "Whether the module resources should be created (true) or not (false)"
  type        = bool
  default     = true
}
