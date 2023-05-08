terraform {
  required_providers {
    packetfabric = {
      source  = "PacketFabric/packetfabric"
      version = ">= 1.5.0"
    }
    aws = {
      source  = "hashicorp/aws"
      version = ">= 4.62.0"
    }
    google = {
      source  = "hashicorp/google"
      version = ">= 4.61.0"
    }
  }
  required_version = ">= 1.3.0"
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
data "packetfabric_billing" "billing_cr" {
  provider   = packetfabric
  circuit_id = packetfabric_cloud_router.cr.id
}

module "aws" {
  source                       = "./aws"
  module_enabled               = var.aws_cloud_router_connections != null
  name                         = var.name
  labels                       = var.labels
  google_in_prefixes           = try(module.google.google_in_prefixes, [])
  cr_id                        = packetfabric_cloud_router.cr.id
  aws_cloud_router_connections = var.aws_cloud_router_connections
}

module "google" {
  source                          = "./google"
  module_enabled                  = var.google_cloud_router_connections != null
  name                            = var.name
  labels                          = var.labels
  aws_in_prefixes                 = try(module.aws.aws_in_prefixes, [])
  cr_id                           = packetfabric_cloud_router.cr.id
  google_cloud_router_connections = var.google_cloud_router_connections
}

locals {
  cr_monthly_prices = flatten([
    for billing in data.packetfabric_billing.billing_cr.billings : [
      for billable in billing.billables :
        billable.price * (billable.price_type == "monthly" ? 1 : 0)
    ]
  ])
  cr_monthly_price = sum(local.cr_monthly_prices)

  aws_crc_primary_monthly_prices = try(flatten([
    for billing in module.aws.aws_crc_primary_billing : [
      for billable in billing.billables :
        billable.price * (billable.price_type == "monthly" ? 1 : 0)
    ]
  ]), [])
  aws_crc_primary_monthly_price = try(sum(local.aws_crc_primary_monthly_prices), 0)

  aws_crc_secondary_monthly_prices = try(flatten([
    for billing in module.aws.aws_crc_secondary_billing : [
      for billable in billing.billables :
        billable.price * (billable.price_type == "monthly" ? 1 : 0)
    ]
  ]), [])
  aws_crc_secondary_monthly_price = try(sum(local.aws_crc_secondary_monthly_prices), 0)

  google_crc_primary_monthly_prices = try(flatten([
    for billing in module.google.google_crc_primary_billing : [
      for billable in billing.billables :
        billable.price * (billable.price_type == "monthly" ? 1 : 0)
    ]
  ]), [])
  google_crc_primary_monthly_price = try(sum(local.google_crc_primary_monthly_prices), 0)

  google_crc_secondary_monthly_prices = try(flatten([
    for billing in module.google.google_crc_secondary_billing : [
      for billable in billing.billables :
        billable.price * (billable.price_type == "monthly" ? 1 : 0)
    ]
  ]), [])
  google_crc_secondary_monthly_price = try(sum(local.google_crc_secondary_monthly_prices), 0)

  total_price_mrc = local.cr_monthly_price + local.aws_crc_primary_monthly_price + local.aws_crc_secondary_monthly_price + local.google_crc_primary_monthly_price + local.google_crc_secondary_monthly_price
}
