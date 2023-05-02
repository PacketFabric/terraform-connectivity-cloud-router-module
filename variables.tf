# Common variables
variable "name" {
  description = "The base name all Network services created in PacketFabric, Google and AWS."
  type        = string
}
variable "labels" {
  description = "The labels to be assigned to the PacketFabric Cloud Router and Cloud Router Connections."
  type        = list(string)
  default     = ["terraform-cts"]
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
  default     = "10Gbps"
}

variable "regions" {
  description = "The list of regions for the PacketFabric Cloud Router."
  type        = list(string)
  default     = ["US", "UK"]
}

variable "cr_id" {
  default     = null
  description = "The Cloud Router Circuit ID created by this module automatically."
}

# PacketFabric Cloud Router Connection AWS
variable "aws_cloud_router_connections" {
  description = "An object representing the AWS Cloud Router Connections."
  type = object({
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
  })
  default = null
}

# PacketFabric Cloud Router Conection Google
variable "google_cloud_router_connections" {
  description = "A object representing the Google Cloud Router Connections."
  type = object({
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
  })
  default = null
}

# # PacketFabric Cloud Router Conection Azure -- not yet available open an issue on github
# variable "azure_cloud_router_connections" {
#   description = "An object representing the Azure Cloud Router Connections."
#   type = object({
#     azure_region  = string
#     azure_vnet_id = string
#     azure_pop     = string
#     azure_speed   = optional(string)
#     redundant     = optional(bool)
#     bgp_prefixes = optional(list(object({
#       prefix = string
#       type   = string
#     })))
#     bgp_prefixes_match_type = optional(string)
#   })
#   default = null
# }

variable "aws_in_prefixes" {
  description = "The Allowed Prefixes from AWS, by default will get all AWS VPC subnets. You can also add additional ones."
  default     = []
}
variable "google_in_prefixes" {
  description = "The Allowed Prefixes from Google Cloud, by default will get all Google VPC subnets. You can also add additional ones."
  default     = []
}
# variable "azure_in_prefixes" {
#   description = "The Allowed Prefixes from Azure Cloud, by default will get all Azure VNet subnets. You can also add additional ones."
#   default     = []
# }