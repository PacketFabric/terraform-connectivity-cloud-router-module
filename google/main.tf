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

# Import Google Credentials to PacketFabric to provision the cloud side of the connection
resource "packetfabric_cloud_provider_credential_google" "google_creds" {
  provider    = packetfabric
  count       = length(var.google_cloud_router_connections) > 0 ? 1 : 0
  description = "${var.google_cloud_router_connections[0].name != null ? var.google_cloud_router_connections[0].name : var.name}-google"
  # using env var GOOGLE_CREDENTIALS
}

# Get the Google VPC
data "google_compute_network" "google_vpc" {
  provider = google
  count    = length(var.google_cloud_router_connections)
  project  = var.google_cloud_router_connections[count.index].google_project
  name     = var.google_cloud_router_connections[count.index].google_network
}

# Get all the subnets in the project
data "google_compute_subnetwork" "google_subnets" {
  provider  = google
  count     = length(flatten(data.google_compute_network.google_vpc[*].subnetworks_self_links))
  self_link = flatten(data.google_compute_network.google_vpc[*].subnetworks_self_links)[count.index]
}

locals {
  # Get the prefixes of the subnets
  google_in_prefixes = {
    for i, subnet in data.google_compute_subnetwork.google_subnets : subnet.self_link => {
      prefix = subnet.ip_cidr_range
    } if subnet.region == var.google_cloud_router_connections[i % length(var.google_cloud_router_connections)].google_region
  }
}

output "google_in_prefixes" {
  value = local.google_in_prefixes
}

# Google Cloud Router
resource "google_compute_router" "google_router" {
  provider = google
  count    = length(var.google_cloud_router_connections)
  name     = var.google_cloud_router_connections[count.index].name != "" ? var.google_cloud_router_connections[count.index].name : var.name
  region   = var.google_cloud_router_connections[count.index].google_region
  project  = var.google_cloud_router_connections[count.index].google_project
  network  = var.google_cloud_router_connections[count.index].google_network
  bgp {
    asn            = 16550 # must be set to 16550 for partner connection
    advertise_mode = "CUSTOM"
  }
  lifecycle {
    # advertised_ip_ranges managed via BGP prefixes in configured in packetfabric_cloud_router_connection_google
    # asn could be changed to a private ASN by PacketFabric in case of multiple Google connections in the same cloud router
    ignore_changes = [
      bgp[0].advertised_ip_ranges,
      bgp[0].asn
    ]
  }
}

# PacketFabric Google Cloud Router Connection(s)
resource "packetfabric_cloud_router_connection_google" "crc_google_primary" {
  provider    = packetfabric
  count       = length(var.google_cloud_router_connections)
  description = coalesce(var.google_cloud_router_connections[count.index].name, var.name, "") != "" ? var.google_cloud_router_connections[count.index].name : "${var.name}-primary"
  labels      = length(coalesce(var.google_cloud_router_connections[count.index].labels, var.labels, [])) > 0 ? var.google_cloud_router_connections[count.index].labels : var.labels
  circuit_id  = var.cr_id
  pop         = var.google_cloud_router_connections[count.index].google_pop
  speed       = coalesce(var.google_cloud_router_connections[count.index].google_speed, "1Gbps")
  cloud_settings {
    credentials_uuid                = packetfabric_cloud_provider_credential_google.google_creds[0].id
    google_project_id               = var.google_cloud_router_connections[count.index].google_project
    google_region                   = var.google_cloud_router_connections[count.index].google_region
    google_vlan_attachment_name     = coalesce(var.google_cloud_router_connections[count.index].name, var.name, "") != "" ? var.google_cloud_router_connections[count.index].name : "${var.name}-primary"
    google_cloud_router_name        = google_compute_router.google_router[count.index].name
    google_vpc_name                 = var.google_cloud_router_connections[count.index].google_network
    google_edge_availability_domain = 1
    mtu                             = 1500
    bgp_settings {
      remote_asn = coalesce(var.google_cloud_router_connections[count.index].google_asn, 16550)
      # OUT: Allowed Prefixes to Cloud (to Google)
      dynamic "prefixes" {
        for_each = (
            (
              length(var.aws_in_prefixes) == 0 
              # && length(coalesce(var.aws_cloud_router_connections[count.index].bgp_prefixes, [])) == 0
            ) 
            && (
              length(var.azure_in_prefixes) == 0
              # && length(coalesce(var.azure_cloud_router_connections[count.index].bgp_prefixes, [])) == 0
            )
          ) ? ["0.0.0.0/0"] : toset(concat(
            [for prefix in var.aws_in_prefixes : prefix.prefix],
            [for prefix in var.azure_in_prefixes : prefix.prefix],
            length(coalesce(var.google_cloud_router_connections[count.index].bgp_prefixes, [])) > 0 ? [for prefix in var.google_cloud_router_connections[count.index].bgp_prefixes : prefix.prefix if prefix.type == "out"] : []
        ))
        content {
          prefix     = prefixes.value
          type       = "out"
          match_type = coalesce(var.google_cloud_router_connections[count.index].bgp_prefixes_match_type, "exact")
        }
      }
      # IN: Allowed Prefixes from Cloud (from Google)
      dynamic "prefixes" {
        for_each = toset(concat(
          [for prefix in local.google_in_prefixes : prefix.prefix],
          length(coalesce(var.google_cloud_router_connections[count.index].bgp_prefixes, [])) > 0 ? [for prefix in var.google_cloud_router_connections[count.index].bgp_prefixes : prefix.prefix if prefix.type == "in"] : []
        ))
        content {
          prefix     = prefixes.value
          type       = "in"
          match_type = coalesce(var.google_cloud_router_connections[count.index].bgp_prefixes_match_type, "exact")
        }
      }
    }
  }
}

# Create the redundant connection if redundant set to true
resource "packetfabric_cloud_router_connection_google" "crc_google_secondary" {
  provider  = packetfabric
  for_each  = { for idx, connection in var.google_cloud_router_connections : idx => connection if connection.redundant == true }

  description = "${each.value.name != "" ? each.value.name : var.name}-secondary"
  labels      = each.value.labels != null ? each.value.labels : var.labels
  circuit_id  = var.cr_id
  pop         = each.value.google_pop
  speed       = each.value.google_speed != null ? each.value.google_speed : "1Gbps"

  cloud_settings {
    credentials_uuid                = packetfabric_cloud_provider_credential_google.google_creds[0].id
    google_project_id               = each.value.google_project
    google_region                   = each.value.google_region
    google_vlan_attachment_name     = "${each.value.name != "" ? each.value.name : var.name}-secondary"
    google_cloud_router_name        = google_compute_router.google_router[each.key].name
    google_vpc_name                 = each.value.google_network
    google_edge_availability_domain = 2
    mtu                             = 1500
    bgp_settings {
      remote_asn = each.value.google_asn != null ? each.value.google_asn : 16550
      # # Secondary - Set AS Prepend to 5 and Local Pref to 1 to prioritized traffic to the primary
      # as_prepend       = 5
      # local_preference = 1
      # OUT: Allowed Prefixes to Cloud (to Google)
      dynamic "prefixes" {
        # TODO: missing 0.0.0.0/ if no out prefixes from other clouds
        for_each = each.value.redundant == true ? toset(concat(
          [for prefix in var.aws_in_prefixes : prefix.prefix],
          [for prefix in var.azure_in_prefixes : prefix.prefix],
          each.value.bgp_prefixes != null ? [for prefix in each.value.bgp_prefixes : prefix.prefix if prefix.type == "out"] : []
        )) : []

        content {
          prefix     = prefixes.value
          type       = "out"
          match_type = each.value.bgp_prefixes_match_type != null ? each.value.bgp_prefixes_match_type : "exact"
        }
      }
      # IN: Allowed Prefixes from Cloud (from Google)
      dynamic "prefixes" {
        for_each = each.value.redundant == true ? toset(concat(
          [for prefix in local.google_in_prefixes : prefix.prefix],
          each.value.bgp_prefixes != null ? [for prefix in each.value.bgp_prefixes : prefix.prefix if prefix.type == "in"] : []
        )) : []

        content {
          prefix     = prefixes.value
          type       = "in"
          match_type = each.value.bgp_prefixes_match_type != null ? each.value.bgp_prefixes_match_type : "exact"
        }
      }
    }
  }
}

output "cloud_router_connection_google_primary" {
  value = packetfabric_cloud_router_connection_google.crc_google_primary
}

output "cloud_router_connection_google_secondary" {
  value = packetfabric_cloud_router_connection_google.crc_google_secondary
}