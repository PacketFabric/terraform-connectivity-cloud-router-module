terraform {
  required_providers {
    # Note: The PacketFabric provider is a third-party provider and not an official HashiCorp provider.
    # As a result, it is necessary to specify the source of the provider in both parent and child modules.
    packetfabric = {
      source  = "PacketFabric/packetfabric"
      version = ">= 1.6.0"
    }
  }
}

provider "aws" {
  # we have to set it to something in case no aws connections are defined
  region = var.aws_cloud_router_connections != null ? var.aws_cloud_router_connections.aws_region : "us-east-1"
  alias  = "alias1"
}

# Import AWS Credentials to PacketFabric to provision the cloud side of the connection
resource "packetfabric_cloud_provider_credential_aws" "aws_creds" {
  provider    = packetfabric
  count       = var.module_enabled ? 1 : 0
  description = "${var.aws_cloud_router_connections.name}-aws"
  # using env var AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY
}

output "aws_creds" {
  value = length(packetfabric_cloud_provider_credential_aws.aws_creds) > 0 ? packetfabric_cloud_provider_credential_aws.aws_creds[0].id : null
}

# Get the network prefix from the AWS VPC
data "aws_vpc" "aws_vpc" {
  provider = aws.alias1
  count    = var.module_enabled ? 1 : 0
  id       = var.aws_cloud_router_connections.aws_vpc_id
}

locals {
  # Get the prefixes of the subnets
  aws_in_prefixes = var.aws_cloud_router_connections != null ? {
    "vpc_cidr" = {
      prefix = data.aws_vpc.aws_vpc[0].cidr_block
    }
  } : {}
}

output "aws_in_prefixes" {
  value = local.aws_in_prefixes
}

# AWS Virtual Private Gateway
resource "aws_vpn_gateway" "vpn_gw" {
  provider        = aws.alias1
  count           = var.module_enabled ? 1 : 0
  amazon_side_asn = var.aws_cloud_router_connections.aws_asn1 != null ? var.aws_cloud_router_connections.aws_asn1 : 64512
  vpc_id          = var.aws_cloud_router_connections.aws_vpc_id
  tags = {
    Name = var.aws_cloud_router_connections.name
  }
}

# To avoid the error conflicting pending workflow when deleting aws_vpn_gateway during the destroy
resource "time_sleep" "delay" {
  count            = var.module_enabled ? 1 : 0
  create_duration  = "0s"
  destroy_duration = "2m"

  depends_on = [
    aws_vpn_gateway.vpn_gw[0],
    aws_dx_gateway.direct_connect_gw[0]
  ]
}

resource "aws_dx_gateway" "direct_connect_gw" {
  provider        = aws.alias1
  count           = var.module_enabled ? 1 : 0
  name            = var.aws_cloud_router_connections.name
  amazon_side_asn = var.aws_cloud_router_connections.aws_asn2 != null ? var.aws_cloud_router_connections.aws_asn2 : 64513
}

# Associate Virtual Private GW to Direct Connect GW
resource "aws_dx_gateway_association" "virtual_private_gw_to_direct_connect" {
  provider              = aws.alias1
  count                 = var.module_enabled ? 1 : 0
  dx_gateway_id         = aws_dx_gateway.direct_connect_gw[0].id
  associated_gateway_id = aws_vpn_gateway.vpn_gw[0].id
  # allowed_prefixes managed via BGP prefixes in configured in packetfabric_cloud_router_connection_aws
  timeouts {
    create = "2h"
    delete = "2h"
  }
  depends_on = [time_sleep.delay[0]]
}

# Get automatically the zone for the pop
data "packetfabric_locations_cloud" "locations_pop_zones_aws" {
  count                 = var.module_enabled ? 1 : 0
  provider              = packetfabric
  cloud_provider        = "aws"
  cloud_connection_type = "hosted"
  has_cloud_router      = true
  pop                   = var.aws_cloud_router_connections.aws_pop
}

# PacketFabric AWS Cloud Router Connection(s)
resource "packetfabric_cloud_router_connection_aws" "crc_aws_primary" {
  provider    = packetfabric
  count       = var.module_enabled ? 1 : 0
  description = "${var.aws_cloud_router_connections.name}-primary"
  labels      = var.aws_cloud_router_connections.labels != null ? var.aws_cloud_router_connections.labels : var.labels
  circuit_id  = var.cr_id
  pop         = var.aws_cloud_router_connections.aws_pop
  zone        = data.packetfabric_locations_cloud.locations_pop_zones_aws[0].cloud_locations[0].zones[0]
  speed       = var.aws_cloud_router_connections.aws_speed != null ? var.aws_cloud_router_connections.aws_speed : "1Gbps"
  cloud_settings {
    credentials_uuid = packetfabric_cloud_provider_credential_aws.aws_creds[0].id
    aws_region       = var.aws_cloud_router_connections.aws_region
    aws_vif_type     = "private"
    mtu              = 1500
    aws_gateways {
      type = "directconnect"
      id   = aws_dx_gateway.direct_connect_gw[0].id
    }
    aws_gateways {
      type   = "private"
      id     = aws_vpn_gateway.vpn_gw[0].id
      vpc_id = var.aws_cloud_router_connections.aws_vpc_id
    }
    bgp_settings {
      # # Primary - Set AS Prepend to 1 and Local Pref to 10 to prioritized traffic to the primary
      # as_prepend       = 1
      # local_preference = 10
      # OUT: Allowed Prefixes to Cloud (to AWS)
      dynamic "prefixes" {
        for_each = (
          (
            length(var.aws_in_prefixes) == 0 &&
            length(try(coalesce(var.aws_cloud_router_connections[2].bgp_prefixes, []), [])) == 0 &&
            length(try(coalesce(var.aws_cloud_router_connections[3].bgp_prefixes, []), [])) == 0
          )
          &&
          (
            length(var.google_in_prefixes) == 0 &&
          length(try(coalesce(var.google_cloud_router_connections.bgp_prefixes, []), [])) == 0)
          &&
          (
            length(var.azure_in_prefixes) == 0 &&
          length(try(coalesce(var.azure_cloud_router_connections.bgp_prefixes, []), [])) == 0)
          ) ? ["0.0.0.0/0"] : toset(concat(
            [for prefix in var.aws_in_prefixes : prefix.prefix],
            [for prefix in var.google_in_prefixes : prefix.prefix],
            [for prefix in var.azure_in_prefixes : prefix.prefix],
            var.aws_cloud_router_connections.bgp_prefixes != null ? [for prefix in var.aws_cloud_router_connections.bgp_prefixes : prefix.prefix if prefix.type == "out"] : []
        ))
        content {
          prefix     = prefixes.value
          type       = "out"
          match_type = var.aws_cloud_router_connections.bgp_prefixes_match_type != null ? var.aws_cloud_router_connections.bgp_prefixes_match_type : "exact"
        }
      }
      # IN: Allowed Prefixes from Cloud (from AWS)
      dynamic "prefixes" {
        for_each = toset(concat(
          [for prefix in local.aws_in_prefixes : prefix.prefix],
          var.aws_cloud_router_connections.bgp_prefixes != null ? [for prefix in var.aws_cloud_router_connections.bgp_prefixes : prefix.prefix if prefix.type == "in"] : []
        ))
        content {
          prefix     = prefixes.value
          type       = "in"
          match_type = var.aws_cloud_router_connections.bgp_prefixes_match_type != null ? var.aws_cloud_router_connections.bgp_prefixes_match_type : "exact"
        }
      }
    }
  }
  lifecycle {
    ignore_changes = [
      zone,
    ]
  }
  depends_on = [
    aws_dx_gateway_association.virtual_private_gw_to_direct_connect[0]
  ]
}

# Create the redundant connection if redundant set to true
resource "packetfabric_cloud_router_connection_aws" "crc_aws_secondary" {
  provider    = packetfabric
  count       = var.module_enabled ? (var.aws_cloud_router_connections.redundant == true ? 1 : 0) : 0
  description = "${var.aws_cloud_router_connections.name}-secondary"
  labels      = var.aws_cloud_router_connections.labels != null ? var.aws_cloud_router_connections.labels : var.labels
  circuit_id  = var.cr_id
  pop         = var.aws_cloud_router_connections.aws_pop
  zone        = data.packetfabric_locations_cloud.locations_pop_zones_aws[0].cloud_locations[0].zones[1]
  speed       = var.aws_cloud_router_connections.aws_speed != null ? var.aws_cloud_router_connections.aws_speed : "1Gbps"
  cloud_settings {
    credentials_uuid = packetfabric_cloud_provider_credential_aws.aws_creds[0].id
    aws_region       = var.aws_cloud_router_connections.aws_region
    aws_vif_type     = "private"
    mtu              = 1500
    aws_gateways {
      type = "directconnect"
      id   = aws_dx_gateway.direct_connect_gw[0].id
    }
    aws_gateways {
      type   = "private"
      id     = aws_vpn_gateway.vpn_gw[0].id
      vpc_id = var.aws_cloud_router_connections.aws_vpc_id
    }
    bgp_settings {
      # # Secondary - Set AS Prepend to 5 and Local Pref to 1 to prioritized traffic to the primary
      # as_prepend       = 5
      # local_preference = 1
      # OUT: Allowed Prefixes to Cloud (to AWS)
      dynamic "prefixes" {
        for_each = (
          (
            length(var.aws_in_prefixes) == 0 &&
            length(try(coalesce(var.aws_cloud_router_connections[2].bgp_prefixes, []), [])) == 0 &&
            length(try(coalesce(var.aws_cloud_router_connections[3].bgp_prefixes, []), [])) == 0
          )
          &&
          (
            length(var.google_in_prefixes) == 0 &&
          length(try(coalesce(var.google_cloud_router_connections.bgp_prefixes, []), [])) == 0)
          &&
          (
            length(var.azure_in_prefixes) == 0 &&
          length(try(coalesce(var.azure_cloud_router_connections.bgp_prefixes, []), [])) == 0)
          ) ? ["0.0.0.0/0"] : toset(concat(
            [for prefix in var.aws_in_prefixes : prefix.prefix],
            [for prefix in var.google_in_prefixes : prefix.prefix],
            [for prefix in var.azure_in_prefixes : prefix.prefix],
            var.aws_cloud_router_connections.bgp_prefixes != null ? [for prefix in var.aws_cloud_router_connections.bgp_prefixes : prefix.prefix if prefix.type == "out"] : []
        ))
        content {
          prefix     = prefixes.value
          type       = "out"
          match_type = var.aws_cloud_router_connections.bgp_prefixes_match_type != null ? var.aws_cloud_router_connections.bgp_prefixes_match_type : "exact"
        }
      }
      # IN: Allowed Prefixes from Cloud (from AWS)
      dynamic "prefixes" {
        for_each = toset(concat(
          [for prefix in local.aws_in_prefixes : prefix.prefix],
          var.aws_cloud_router_connections.bgp_prefixes != null ? [for prefix in var.aws_cloud_router_connections.bgp_prefixes : prefix.prefix if prefix.type == "in"] : []
        ))
        content {
          prefix     = prefixes.value
          type       = "in"
          match_type = var.aws_cloud_router_connections.bgp_prefixes_match_type != null ? var.aws_cloud_router_connections.bgp_prefixes_match_type : "exact"
        }
      }
    }
  }
  lifecycle {
    ignore_changes = [
      zone,
    ]
  }
  # Create one connection at a time, especially for update
  depends_on = [
    packetfabric_cloud_router_connection_aws.crc_aws_primary[0]
  ]
}

output "cloud_router_connection_aws_primary" {
  value       = packetfabric_cloud_router_connection_aws.crc_aws_primary
  description = "Primary PacketFabric AWS Cloud Router Connection"
}

output "cloud_router_connection_aws_secondary" {
  value       = packetfabric_cloud_router_connection_aws.crc_aws_secondary
  description = "Secondary PacketFabric AWS Cloud Router Connection (if redundant is true)"
}