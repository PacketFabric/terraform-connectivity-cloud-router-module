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

# Limitation Terraform https://github.com/hashicorp/terraform/issues/24476
provider "aws" {
  region = var.aws_cloud_router_connections != null && length(coalesce(var.aws_cloud_router_connections, [])) > 0 ? var.aws_cloud_router_connections[0].aws_region : "us-east-1"
}

# Import AWS Credentials to PacketFabric to provision the cloud side of the connection
resource "packetfabric_cloud_provider_credential_aws" "aws_creds" {
  provider    = packetfabric
  count       = length(coalesce(var.aws_cloud_router_connections, [])) > 0 ? 1 : 0
  description = var.name
  # description = "${var.aws_cloud_router_connections.name != null ? var.aws_cloud_router_connections.name : var.name}-aws"
  # using env var PF_AWS_ACCESS_KEY_ID and PF_AWS_SECRET_ACCESS_KEY
}

# Get the network prefix from the AWS VPC
data "aws_vpc" "aws_vpc" {
  provider = aws
  count    = length(coalesce(var.aws_cloud_router_connections, []))
  id       = var.aws_cloud_router_connections[count.index].aws_vpc_id
}

# Get the prefixes of the subnets
locals {
  aws_in_prefixes = {
    for idx in range(length(coalesce(var.aws_cloud_router_connections, []))) : "${idx}-${data.aws_vpc.aws_vpc[idx].id}" => {
      prefix = data.aws_vpc.aws_vpc[idx].cidr_block
      region = var.aws_cloud_router_connections[idx].aws_region
    }
  }
}


output "aws_in_prefixes" {
  value = local.aws_in_prefixes
}

# AWS Virtual Private Gateway
resource "aws_vpn_gateway" "vpn_gw" {
  provider        = aws
  count           = length(coalesce(var.aws_cloud_router_connections, []))
  amazon_side_asn = coalesce(var.aws_cloud_router_connections[count.index].aws_asn1, 64512)
  vpc_id          = var.aws_cloud_router_connections[count.index].aws_vpc_id
  tags = {
    Name = "${var.aws_cloud_router_connections[count.index].name}"
  }
}

# To avoid the error conflicting pending workflow when deleting aws_vpn_gateway during the destroy
resource "time_sleep" "delay" {
  for_each = {
    for idx, connection in coalesce(var.aws_cloud_router_connections, []) : idx => connection
  }

  create_duration  = "0s"
  destroy_duration = "2m"

  depends_on = [
    aws_vpn_gateway.vpn_gw[0],
    aws_dx_gateway.direct_connect_gw[0]
  ]
}

resource "aws_dx_gateway" "direct_connect_gw" {
  provider        = aws
  count           = length(coalesce(var.aws_cloud_router_connections, []))
  name            = var.aws_cloud_router_connections[count.index].name
  amazon_side_asn = coalesce(var.aws_cloud_router_connections[count.index].aws_asn2, 64513)
}

# Associate Virtual Private GW to Direct Connect GW
resource "aws_dx_gateway_association" "virtual_private_gw_to_direct_connect" {
  provider = aws
  for_each = {
    for idx, connection in coalesce(var.aws_cloud_router_connections, []) : idx => connection
  }

  dx_gateway_id         = aws_dx_gateway.direct_connect_gw[each.key].id
  associated_gateway_id = aws_vpn_gateway.vpn_gw[each.key].id
  # allowed_prefixes managed via BGP prefixes in configured in packetfabric_cloud_router_connection_aws
  timeouts {
    create = "2h"
    delete = "2h"
  }
  depends_on = [time_sleep.delay[0]]
}

# Get automatically the zone for the pop
data "packetfabric_locations_cloud" "locations_pop_zones_aws" {
  count                 = length(coalesce(var.aws_cloud_router_connections, []))
  provider              = packetfabric
  cloud_provider        = "aws"
  cloud_connection_type = "hosted"
  has_cloud_router      = true
  pop                   = var.aws_cloud_router_connections[count.index].aws_pop
}

# PacketFabric AWS Cloud Router Connection(s)
resource "packetfabric_cloud_router_connection_aws" "crc_aws_primary" {
  provider    = packetfabric
  count       = length(coalesce(var.aws_cloud_router_connections, []))
  description = "${var.aws_cloud_router_connections[count.index].name}-primary"
  labels      = length(coalesce(var.aws_cloud_router_connections[count.index].labels, var.labels, [])) > 0 ? var.aws_cloud_router_connections[count.index].labels : var.labels
  circuit_id  = var.cr_id
  pop         = var.aws_cloud_router_connections[count.index].aws_pop
  zone        = data.packetfabric_locations_cloud.locations_pop_zones_aws[count.index].cloud_locations[0].zones[0]
  speed       = coalesce(var.aws_cloud_router_connections[count.index].aws_speed, "1Gbps")
  cloud_settings {
    credentials_uuid = packetfabric_cloud_provider_credential_aws.aws_creds[0].id
    aws_region       = var.aws_cloud_router_connections[count.index].aws_region
    aws_vif_type     = "private"
    mtu              = 1500
    aws_gateways {
      type = "directconnect"
      id   = aws_dx_gateway.direct_connect_gw[count.index].id
    }
    aws_gateways {
      type   = "private"
      id     = aws_vpn_gateway.vpn_gw[count.index].id
      vpc_id = var.aws_cloud_router_connections[count.index].aws_vpc_id
    }
    bgp_settings {
      # # Primary - Set AS Prepend to 1 and Local Pref to 10 to prioritized traffic to the primary
      # as_prepend       = 1
      # local_preference = 10
      # OUT: Allowed Prefixes to Cloud (to AWS)
      dynamic "prefixes" {
        for_each = (
          (
            length(var.google_in_prefixes) == 0 &&
            length(coalesce(var.google_cloud_router_connections, [])[*].bgp_prefixes[count.index] == null ? [] : var.google_cloud_router_connections[*].bgp_prefixes[count.index]) == 0
          )
          && (
            length(var.azure_in_prefixes) == 0 &&
            length(coalesce(var.azure_cloud_router_connections, [])[*].bgp_prefixes[count.index] == null ? [] : var.azure_cloud_router_connections[*].bgp_prefixes[count.index]) == 0
          )
          ) ? ["0.0.0.0/0"] : toset(concat(
            [for prefix in var.google_in_prefixes : prefix.prefix],
            [for prefix in var.azure_in_prefixes : prefix.prefix],
            length(coalesce(var.aws_cloud_router_connections[count.index].bgp_prefixes, [])) > 0 ? [for prefix in var.aws_cloud_router_connections[count.index].bgp_prefixes : prefix.prefix if prefix.type == "out"] : []
        ))
        content {
          prefix     = prefixes.value
          type       = "out"
          match_type = coalesce(var.aws_cloud_router_connections[count.index].bgp_prefixes_match_type, "exact")
        }
      }
      # IN: Allowed Prefixes from Cloud (from AWS)
      dynamic "prefixes" {
        for_each = toset(concat(
          [for key, value in local.aws_in_prefixes : value.prefix if value.region == var.aws_cloud_router_connections[count.index].aws_region],
          length(coalesce(var.aws_cloud_router_connections[count.index].bgp_prefixes, [])) > 0 ? [for prefix in var.aws_cloud_router_connections[count.index].bgp_prefixes : prefix.prefix if prefix.type == "in"] : []
        ))
        content {
          prefix     = prefixes.value
          type       = "in"
          match_type = coalesce(var.aws_cloud_router_connections[count.index].bgp_prefixes_match_type, "exact")
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
  provider = packetfabric
  for_each = {
    for idx, connection in coalesce(var.aws_cloud_router_connections, []) : idx => connection if connection.redundant == true
  }
  description = "${each.value.name}-secondary"
  labels      = each.value.labels != null ? each.value.labels : var.labels
  circuit_id  = var.cr_id
  pop         = each.value.aws_pop
  zone        = data.packetfabric_locations_cloud.locations_pop_zones_aws[each.key].cloud_locations[0].zones[1]
  speed       = each.value.aws_speed != null ? each.value.aws_speed : "1Gbps"
  cloud_settings {
    credentials_uuid = packetfabric_cloud_provider_credential_aws.aws_creds[0].id
    aws_region       = each.value.aws_region
    aws_vif_type     = "private"
    mtu              = 1500
    aws_gateways {
      type = "directconnect"
      id   = aws_dx_gateway.direct_connect_gw[each.key].id
    }
    aws_gateways {
      type   = "private"
      id     = aws_vpn_gateway.vpn_gw[each.key].id
      vpc_id = each.value.aws_vpc_id
    }
    bgp_settings {
      # # Secondary - Set AS Prepend to 5 and Local Pref to 1 to prioritized traffic to the primary
      # as_prepend       = 5
      # local_preference = 1
      # OUT: Allowed Prefixes to Cloud (to AWS)
      dynamic "prefixes" {
        for_each = (
          (
            length(var.google_in_prefixes) == 0 &&
            length(coalesce(var.google_cloud_router_connections, [])[*].bgp_prefixes[each.key] == null ? [] : var.google_cloud_router_connections[*].bgp_prefixes[each.key]) == 0
          )
          && (
            length(var.azure_in_prefixes) == 0 &&
            length(coalesce(var.azure_cloud_router_connections, [])[*].bgp_prefixes[each.key] == null ? [] : var.azure_cloud_router_connections[*].bgp_prefixes[each.key]) == 0
          )
          ) ? ["0.0.0.0/0"] : toset(concat(
            [for prefix in var.google_in_prefixes : prefix.prefix],
            [for prefix in var.azure_in_prefixes : prefix.prefix],
            length(coalesce(each.value.bgp_prefixes, [])) > 0 ? [for prefix in each.value.bgp_prefixes : prefix.prefix if prefix.type == "out"] : []
        ))
        content {
          prefix     = prefixes.value
          type       = "out"
          match_type = coalesce(each.value.bgp_prefixes_match_type, "exact")
        }
      }
      # IN: Allowed Prefixes from Cloud (from AWS)
      dynamic "prefixes" {
        for_each = toset(concat(
          [for key, value in local.aws_in_prefixes : value.prefix if value.region == var.aws_cloud_router_connections[each.key].aws_region],
          length(coalesce(each.value.bgp_prefixes, [])) > 0 ? [for prefix in each.value.bgp_prefixes : prefix.prefix if prefix.type == "in"] : []
        ))
        content {
          prefix     = prefixes.value
          type       = "in"
          match_type = coalesce(each.value.bgp_prefixes_match_type, "exact")
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
