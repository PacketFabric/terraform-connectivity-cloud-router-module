# Common variables
variable "name" {
  description = "The base name all Network services created in PacketFabric, Google and AWS."
  type        = string
}
variable "labels" {
  description = "The labels to be assigned to the PacketFabric Cloud Router and Cloud Router Connections."
  type        = list(string)
  default     = ["terraform"]
}

# PacketFabric Cloud Router
variable "asn" {
  description = "The Autonomous System Number (ASN) for the PacketFabric Cloud Router."
  type        = number
  default     = 4556 # default to PacketFabric ASN
}

variable "capacity" {
  description = "The capacity of the PacketFabric Cloud Router."
  type        = string
  default     = ">100Gbps"
}

variable "regions" {
  description = "The list of regions for the PacketFabric Cloud Router."
  type        = list(string)
  default     = ["US"]
}

variable "cr_id" {
  default     = null
  description = "The Cloud Router Circuit ID created by this module automatically."
}

# PacketFabric Cloud Router Connection AWS
variable "aws_cloud_router_connections" {
  description = "List of objects representing the AWS Cloud Router Connections."
  type = list(object({
    name       = optional(string)
    labels     = optional(list(string))
    aws_region = string
    aws_vpc_id = string
    aws_asn1   = optional(number)
    aws_asn2   = optional(number)
    aws_pop    = string
    aws_speed  = optional(string)
    redundant  = optional(bool)
    bgp_prefixes = optional(list(object({
      prefix = string
      type   = string
    })))
    bgp_prefixes_match_type = optional(string)
  }))
  default = null

  validation {
    condition     = length(coalesce(var.aws_cloud_router_connections, [])) <= 1
    error_message = "You must provide no more than one AWS Cloud Router Connection."
  }
}

# PacketFabric Cloud Router Conection Google
variable "google_cloud_router_connections" {
  description = "List of objects representing the Google Cloud Router Connections."
  type = list(object({
    name           = optional(string)
    labels         = optional(list(string))
    google_project = string
    google_region  = string
    google_network = string
    google_asn     = optional(number)
    google_pop     = string
    google_speed   = optional(string)
    redundant      = optional(bool)
    bgp_prefixes = optional(list(object({
      prefix = string
      type   = string
    })))
    bgp_prefixes_match_type = optional(string)
  }))
  default = null
}

# PacketFabric Cloud Router Conection Azure -- not yet available open an issue on github
variable "azure_cloud_router_connections" {
  description = "List of objects representing the Azure Cloud Router Connections."
  type = list(object({
    name                  = optional(string)
    labels                = optional(list(string))
    azure_region          = string
    azure_resource_group  = string
    azure_vnet            = string
    azure_pop             = string
    azure_speed           = optional(string)
    azure_subscription_id = optional(string)
    skip_gateway          = optional(bool)
    redundant             = optional(bool)
    bgp_prefixes = optional(list(object({
      prefix = string
      type   = string
    })))
    bgp_prefixes_match_type = optional(string)
    provider                = optional(string) # Use "Packet Fabric Test" for internal PF dev testing
  }))
  default = null

  validation {
    condition     = length(coalesce(var.azure_cloud_router_connections, [])) <= 1
    error_message = "You must provide no more than one Azure Cloud Router Connection."
  }
}

variable "aws_in_prefixes" {
  description = "The Allowed Prefixes from AWS, by default will get all AWS VPC subnets. You can also add additional ones."
  default     = []
}
variable "google_in_prefixes" {
  description = "The Allowed Prefixes from Google Cloud, by default will get all Google VPC subnets. You can also add additional ones."
  default     = []
}
variable "azure_in_prefixes" {
  description = "The Allowed Prefixes from Azure Cloud, by default will get all Azure VNet subnets. You can also add additional ones."
  default     = []
}