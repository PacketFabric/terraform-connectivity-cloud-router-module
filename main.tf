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
  # required_version = ">= 1.3.0"
  # for NIA branch only
  required_version = ">= 1.1.0, < 1.3.0"
  experiments      = [module_variable_optional_attrs] # until consul-terraform-sync supports terraform v1.3+
}

# PacketFabric Cloud Router
resource "packetfabric_cloud_router" "cr" {
  provider = packetfabric
  name     = var.name
  asn      = var.asn
  capacity = var.capacity
  regions  = var.regions
  labels   = var.labels
}

module "aws" {
  source                       = "./aws"
  module_enabled               = length(coalesce(var.aws_cloud_router_connections, [])) > 0
  name                         = var.name
  labels                       = var.labels
  google_in_prefixes           = try(module.google.google_in_prefixes, [])
  azure_in_prefixes            = try(module.azure.azure_in_prefixes, [])
  cr_id                        = packetfabric_cloud_router.cr.id
  aws_cloud_router_connections = var.aws_cloud_router_connections
}

module "google" {
  source                          = "./google"
  module_enabled                  = length(coalesce(var.google_cloud_router_connections, [])) > 0
  name                            = var.name
  labels                          = var.labels
  aws_in_prefixes                 = try(module.aws.aws_in_prefixes, [])
  azure_in_prefixes               = try(module.azure.azure_in_prefixes, [])
  cr_id                           = packetfabric_cloud_router.cr.id
  google_cloud_router_connections = var.google_cloud_router_connections
}

module "azure" {
  source                         = "./azure"
  module_enabled                 = length(coalesce(var.azure_cloud_router_connections, [])) > 0
  name                           = var.name
  labels                         = var.labels
  aws_in_prefixes                = try(module.aws.aws_in_prefixes, [])
  google_in_prefixes             = try(module.google.google_in_prefixes, [])
  cr_id                          = packetfabric_cloud_router.cr.id
  cr_asn                         = var.asn
  azure_cloud_router_connections = var.azure_cloud_router_connections
}