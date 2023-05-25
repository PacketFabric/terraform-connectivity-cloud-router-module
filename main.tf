terraform {
  required_providers {
    packetfabric = {
      source  = "PacketFabric/packetfabric"
      version = ">= 1.6.0"
    }
    aws = {
      source  = "hashicorp/aws"
      version = ">= 4.62.0"
    }
    google = {
      source  = "hashicorp/google"
      version = ">= 4.61.0"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 3.56.0"
    }
  }
  # for CR module only
  required_version = ">= 1.3.0"
  # for NIA only
  # required_version = ">= 1.1.0, < 1.3.0"
  # experiments      = [module_variable_optional_attrs] # until consul-terraform-sync supports terraform v1.3+
}

# PacketFabric Cloud Router
resource "packetfabric_cloud_router" "cr" {
  count    = var.cr_id == null ? 1 : 0
  provider = packetfabric
  name     = var.name
  asn      = var.asn
  capacity = var.capacity
  regions  = var.regions
  labels   = var.labels
}

module "aws1" {
  source             = "./aws1"
  module_enabled     = length(coalesce(var.aws_cloud_router_connections, [])) >= 1
  labels             = var.labels
  google_in_prefixes = try(module.google.google_in_prefixes, [])
  azure_in_prefixes  = try(module.azure.azure_in_prefixes, [])
  aws_in_prefixes = concat(
    try(values(module.aws2.aws_in_prefixes), []),
    try(values(module.aws3.aws_in_prefixes), [])
  )
  cr_id                        = var.cr_id != null ? var.cr_id : packetfabric_cloud_router.cr[0].id
  aws_cloud_router_connections = var.aws_cloud_router_connections != null && length(coalesce(var.aws_cloud_router_connections, [])) >= 1 ? var.aws_cloud_router_connections[0] : null

}

module "aws2" {
  source             = "./aws2"
  module_enabled     = length(coalesce(var.aws_cloud_router_connections, [])) >= 2
  labels             = var.labels
  google_in_prefixes = try(module.google.google_in_prefixes, [])
  azure_in_prefixes  = try(module.azure.azure_in_prefixes, [])
  aws_in_prefixes = concat(
    try(values(module.aws1.aws_in_prefixes), []),
    try(values(module.aws3.aws_in_prefixes), [])
  )
  cr_id                        = var.cr_id != null ? var.cr_id : packetfabric_cloud_router.cr[0].id
  aws_cloud_router_connections = var.aws_cloud_router_connections != null && length(coalesce(var.aws_cloud_router_connections, [])) >= 2 ? var.aws_cloud_router_connections[1] : null
  aws_creds                    = module.aws1.aws_creds
}

module "aws3" {
  source             = "./aws3"
  module_enabled     = length(coalesce(var.aws_cloud_router_connections, [])) >= 3
  labels             = var.labels
  google_in_prefixes = try(module.google.google_in_prefixes, [])
  azure_in_prefixes  = try(module.azure.azure_in_prefixes, [])
  aws_in_prefixes = concat(
    try(values(module.aws1.aws_in_prefixes), []),
    try(values(module.aws2.aws_in_prefixes), [])
  )
  cr_id                        = var.cr_id != null ? var.cr_id : packetfabric_cloud_router.cr[0].id
  aws_cloud_router_connections = var.aws_cloud_router_connections != null && length(coalesce(var.aws_cloud_router_connections, [])) >= 3 ? var.aws_cloud_router_connections[2] : null
  aws_creds                    = module.aws1.aws_creds
}

module "google" {
  source         = "./google"
  module_enabled = length(coalesce(var.google_cloud_router_connections, [])) > 0
  labels         = var.labels
  aws_in_prefixes = concat(
    try(values(module.aws1.aws_in_prefixes), []),
    try(values(module.aws2.aws_in_prefixes), []),
    try(values(module.aws3.aws_in_prefixes), [])
  )
  azure_in_prefixes               = try(module.azure.azure_in_prefixes, [])
  cr_id                           = var.cr_id != null ? var.cr_id : packetfabric_cloud_router.cr[0].id
  google_cloud_router_connections = var.google_cloud_router_connections
}

module "azure" {
  source         = "./azure"
  module_enabled = length(coalesce(var.azure_cloud_router_connections, [])) > 0
  labels         = var.labels
  aws_in_prefixes = concat(
    try(values(module.aws1.aws_in_prefixes), []),
    try(values(module.aws2.aws_in_prefixes), []),
    try(values(module.aws3.aws_in_prefixes), [])
  )
  google_in_prefixes             = try(module.google.google_in_prefixes, [])
  cr_id                          = var.cr_id != null ? var.cr_id : packetfabric_cloud_router.cr[0].id
  cr_asn                         = var.asn
  azure_cloud_router_connections = var.azure_cloud_router_connections
}