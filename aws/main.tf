terraform {
  required_providers {
    # Note: The PacketFabric provider is a third-party provider and not an official HashiCorp provider.
    # As a result, it is necessary to specify the source of the provider in both parent and child modules.
    packetfabric = {
      source  = "PacketFabric/packetfabric"
      version = ">= 1.5.0"
    }
  }
}

provider "aws" {
  region = var.aws_cloud_router_connections != null ? var.aws_cloud_router_connections.aws_region : "us-east-1"
}

# Import AWS Credentials to PacketFabric to provision the cloud side of the connection
resource "packetfabric_cloud_provider_credential_aws" "aws_creds" {
  provider    = packetfabric
  count       = var.module_enabled ? 1 : 0
  description = "${var.name}-aws"
  # using env var PF_AWS_ACCESS_KEY_ID and PF_AWS_SECRET_ACCESS_KEY
}

# Get the network prefix from the AWS VPC
data "aws_vpc" "aws_vpc" {
  provider = aws
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
  provider        = aws
  count           = var.module_enabled ? 1 : 0
  amazon_side_asn = var.aws_cloud_router_connections.aws_asn1 != null ? var.aws_cloud_router_connections.aws_asn1 : 64512
  vpc_id          = var.aws_cloud_router_connections.aws_vpc_id
  tags = {
    Name = var.name
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
  provider        = aws
  count           = var.module_enabled ? 1 : 0
  name            = var.name
  amazon_side_asn = var.aws_cloud_router_connections.aws_asn2 != null ? var.aws_cloud_router_connections.aws_asn2 : 64513
}

# Associate Virtual Private GW to Direct Connect GW
resource "aws_dx_gateway_association" "virtual_private_gw_to_direct_connect" {
  provider              = aws
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
  description = "${var.name}-primary"
  labels      = var.labels
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
          length(var.google_in_prefixes) == 0 &&
          length(try(coalesce(var.google_cloud_router_connections.bgp_prefixes, []), [])) == 0
          ) ? ["0.0.0.0/0"] : toset(concat(
            [for prefix in var.google_in_prefixes : prefix.prefix],
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

# Wait 30s before getting the billing information
resource "time_sleep" "delay1" {
  count           = var.module_enabled ? 1 : 0
  depends_on      = [packetfabric_cloud_router_connection_aws.crc_aws_primary[0]]
  create_duration = "30s"
}

data "packetfabric_billing" "crc_aws_primary" {
  provider   = packetfabric
  count      = var.module_enabled ? 1 : 0
  circuit_id = packetfabric_cloud_router_connection_aws.crc_aws_primary[0].id
  depends_on = [time_sleep.delay1]
}

# Create the redundant connection if redundant set to true
resource "packetfabric_cloud_router_connection_aws" "crc_aws_secondary" {
  provider    = packetfabric
  count       = var.module_enabled ? (var.aws_cloud_router_connections.redundant == true ? 1 : 0) : 0
  description = "${var.name}-secondary"
  labels      = var.labels
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
          length(var.google_in_prefixes) == 0 &&
          length(try(coalesce(var.google_cloud_router_connections.bgp_prefixes, []), [])) == 0
          ) ? ["0.0.0.0/0"] : toset(concat(
            [for prefix in var.google_in_prefixes : prefix.prefix],
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

# Wait for the secondary connection to be created before getting billing info
resource "time_sleep" "delay2" {
  count           = var.module_enabled ? (var.aws_cloud_router_connections.redundant == true ? 1 : 0) : 0
  depends_on      = [packetfabric_cloud_router_connection_aws.crc_aws_secondary[0]]
  create_duration = "30s"
}

data "packetfabric_billing" "crc_aws_secondary" {
  provider   = packetfabric
  count      = var.module_enabled ? (var.aws_cloud_router_connections.redundant == true ? 1 : 0) : 0
  circuit_id = packetfabric_cloud_router_connection_aws.crc_aws_secondary[0].id
  depends_on = [time_sleep.delay2]
}

output "cloud_router_connection_aws_primary" {
  value       = packetfabric_cloud_router_connection_aws.crc_aws_primary
  description = "Primary PacketFabric AWS Cloud Router Connection"
}

output "cloud_router_connection_aws_secondary" {
  value       = packetfabric_cloud_router_connection_aws.crc_aws_secondary
  description = "Secondary PacketFabric AWS Cloud Router Connection (if redundant is true)"
}

output "aws_crc_primary_billing" {
  description = "Billing information for the primary AWS Cloud Router Connection"
  value       = try(data.packetfabric_billing.crc_aws_primary[0].billings, [])
}

output "aws_crc_secondary_billing" {
  description = "Billing information for the secondary AWS Cloud Router Connection (if created)"
  value       = try(data.packetfabric_billing.crc_aws_secondary[0].billings, [])
}
