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
  count       = var.module_enabled ? 1 : 0
  description = "${var.google_cloud_router_connections.name != null ? var.google_cloud_router_connections.name : var.name}-google"
  # using env var GOOGLE_CREDENTIALS
}

# Get the Google VPC
data "google_compute_network" "google_vpc" {
  provider = google
  count    = var.module_enabled ? 1 : 0
  project  = var.google_cloud_router_connections.google_project
  name     = var.google_cloud_router_connections.google_network
}

# Get all the subnets in the project
data "google_compute_subnetwork" "google_subnets" {
  provider  = google
  for_each  = var.module_enabled ? toset(data.google_compute_network.google_vpc[0].subnetworks_self_links) : toset([])
  self_link = each.value
}

locals {
  # Get the prefixes of the subnets
  google_in_prefixes = var.google_cloud_router_connections != null ? {
    for key, subnet in data.google_compute_subnetwork.google_subnets : key => {
      prefix = subnet.ip_cidr_range
    } if subnet.region == var.google_cloud_router_connections.google_region
  } : {}
}

output "google_in_prefixes" {
  value = local.google_in_prefixes
}

# Google Cloud Router
resource "google_compute_router" "google_router" {
  provider = google
  count    = var.module_enabled ? 1 : 0
  name     = var.google_cloud_router_connections.name != null ? var.google_cloud_router_connections.name : var.name
  region   = var.google_cloud_router_connections.google_region
  project  = var.google_cloud_router_connections.google_project
  network  = var.google_cloud_router_connections.google_network
  bgp {
    asn            = 16550 # must be se to 16550 for partner connection
    advertise_mode = "CUSTOM"
  }
  lifecycle {
    # advertised_ip_ranges managed via BGP prefixes in configured in packetfabric_cloud_router_connection_google
    # asn could be change to a private ASN by PacketFabric in case of multiple google connection in the same cloud router
    ignore_changes = [
      bgp[0].advertised_ip_ranges,
      bgp[0].asn
    ]
  }
}

# PacketFabric Google Cloud Router Connection(s)
resource "packetfabric_cloud_router_connection_google" "crc_google_primary" {
  provider    = packetfabric
  count       = var.module_enabled ? 1 : 0
  description = "${var.google_cloud_router_connections.name != null ? var.google_cloud_router_connections.name : var.name}-primary"
  labels      = var.google_cloud_router_connections.labels != null ? var.google_cloud_router_connections.labels : var.labels
  circuit_id  = var.cr_id
  pop         = var.google_cloud_router_connections.google_pop
  speed       = var.google_cloud_router_connections.google_speed != null ? var.google_cloud_router_connections.google_speed : "1Gbps"
  cloud_settings {
    credentials_uuid                = packetfabric_cloud_provider_credential_google.google_creds[0].id
    google_project_id               = var.google_cloud_router_connections.google_project
    google_region                   = var.google_cloud_router_connections.google_region
    google_vlan_attachment_name     = "${var.google_cloud_router_connections.name != null ? var.google_cloud_router_connections.name : var.name}-primary"
    google_cloud_router_name        = google_compute_router.google_router[0].name
    google_vpc_name                 = var.google_cloud_router_connections.google_network
    google_edge_availability_domain = 1
    mtu                             = 1500
    bgp_settings {
      # # Primary - Set AS Prepend to 1 and Local Pref to 10 to prioritized traffic to the primary
      # as_prepend       = 1
      # local_preference = 10
      remote_asn = var.google_cloud_router_connections.google_asn != null ? var.google_cloud_router_connections.google_asn : 16550
      # OUT: Allowed Prefixes to Cloud (to Google)
      dynamic "prefixes" {
        for_each = (
          (length(var.aws_in_prefixes) == 0 &&
          length(try(coalesce(var.aws_cloud_router_connections.bgp_prefixes, []), [])) == 0) &&
          (length(var.azure_in_prefixes) == 0 &&
          length(try(coalesce(var.azure_cloud_router_connections.bgp_prefixes, []), [])) == 0)
          ) ? ["0.0.0.0/0"] : toset(concat(
            [for prefix in var.aws_in_prefixes : prefix.prefix],
            [for prefix in var.azure_in_prefixes : prefix.prefix],
            var.google_cloud_router_connections.bgp_prefixes != null ? [for prefix in var.google_cloud_router_connections.bgp_prefixes : prefix.prefix if prefix.type == "out"] : []
        ))
        content {
          prefix     = prefixes.value
          type       = "out"
          match_type = var.google_cloud_router_connections.bgp_prefixes_match_type != null ? var.google_cloud_router_connections.bgp_prefixes_match_type : "exact"
        }
      }
      # IN: Allowed Prefixes from Cloud (from Google)
      dynamic "prefixes" {
        for_each = toset(concat(
          [for prefix in local.google_in_prefixes : prefix.prefix],
          var.google_cloud_router_connections.bgp_prefixes != null ? [for prefix in var.google_cloud_router_connections.bgp_prefixes : prefix.prefix if prefix.type == "in"] : []
        ))
        content {
          prefix     = prefixes.value
          type       = "in"
          match_type = var.google_cloud_router_connections.bgp_prefixes_match_type != null ? var.google_cloud_router_connections.bgp_prefixes_match_type : "exact"
        }
      }
    }
  }
}

# Wait 30s before getting the billing information
resource "time_sleep" "delay1" {
  count           = var.module_enabled ? 1 : 0
  depends_on      = [packetfabric_cloud_router_connection_google.crc_google_primary[0]]
  create_duration = "30s"
}

data "packetfabric_billing" "crc_google_primary" {
  provider   = packetfabric
  count      = var.module_enabled ? 1 : 0
  circuit_id = packetfabric_cloud_router_connection_google.crc_google_primary[0].id
  depends_on = [time_sleep.delay1]
}

# Create the redundant connection if redundant set to true
resource "packetfabric_cloud_router_connection_google" "crc_google_secondary" {
  provider    = packetfabric
  count       = var.module_enabled ? (var.google_cloud_router_connections.redundant == true ? 1 : 0) : 0
  description = "${var.google_cloud_router_connections.name != null ? var.google_cloud_router_connections.name : var.name}-secondary"
  labels      = var.google_cloud_router_connections.labels != null ? var.google_cloud_router_connections.labels : var.labels
  circuit_id  = var.cr_id
  pop         = var.google_cloud_router_connections.google_pop
  speed       = var.google_cloud_router_connections.google_speed != null ? var.google_cloud_router_connections.google_speed : "1Gbps"
  cloud_settings {
    credentials_uuid                = packetfabric_cloud_provider_credential_google.google_creds[0].id
    google_project_id               = var.google_cloud_router_connections.google_project
    google_region                   = var.google_cloud_router_connections.google_region
    google_vlan_attachment_name     = "${var.google_cloud_router_connections.name != null ? var.google_cloud_router_connections.name : var.name}-secondary"
    google_cloud_router_name        = google_compute_router.google_router[0].name
    google_vpc_name                 = var.google_cloud_router_connections.google_network
    google_edge_availability_domain = 2
    mtu                             = 1500
    bgp_settings {
      # # Secondary - Set AS Prepend to 5 and Local Pref to 1 to prioritized traffic to the primary
      # as_prepend       = 5
      # local_preference = 1
      remote_asn = var.google_cloud_router_connections.google_asn != null ? var.google_cloud_router_connections.google_asn : 16550
      # OUT: Allowed Prefixes to Cloud (to Google)
      dynamic "prefixes" {
        for_each = (
          (length(var.aws_in_prefixes) == 0 &&
          length(try(coalesce(var.aws_cloud_router_connections.bgp_prefixes, []), [])) == 0) &&
          (length(var.azure_in_prefixes) == 0 &&
          length(try(coalesce(var.azure_cloud_router_connections.bgp_prefixes, []), [])) == 0)
          ) ? ["0.0.0.0/0"] : toset(concat(
            [for prefix in var.aws_in_prefixes : prefix.prefix],
            [for prefix in var.azure_in_prefixes : prefix.prefix],
            var.google_cloud_router_connections.bgp_prefixes != null ? [for prefix in var.google_cloud_router_connections.bgp_prefixes : prefix.prefix if prefix.type == "out"] : []
        ))
        content {
          prefix     = prefixes.value
          type       = "out"
          match_type = var.google_cloud_router_connections.bgp_prefixes_match_type != null ? var.google_cloud_router_connections.bgp_prefixes_match_type : "exact"
        }
      }
      # IN: Allowed Prefixes from Cloud (from Google)
      dynamic "prefixes" {
        for_each = toset(concat(
          [for prefix in local.google_in_prefixes : prefix.prefix],
          var.google_cloud_router_connections.bgp_prefixes != null ? [for prefix in var.google_cloud_router_connections.bgp_prefixes : prefix.prefix if prefix.type == "in"] : []
        ))
        content {
          prefix     = prefixes.value
          type       = "in"
          match_type = var.google_cloud_router_connections.bgp_prefixes_match_type != null ? var.google_cloud_router_connections.bgp_prefixes_match_type : "exact"
        }
      }
    }
  }
  # Create one connection at a time, especially for update
  depends_on = [
    packetfabric_cloud_router_connection_google.crc_google_primary[0]
  ]
}

# Wait for the secondary connection to be created before checking billing
resource "time_sleep" "delay2" {
  count           = var.module_enabled ? (var.google_cloud_router_connections.redundant == true ? 1 : 0) : 0
  depends_on      = [packetfabric_cloud_router_connection_google.crc_google_secondary[0]]
  create_duration = "30s"
}

data "packetfabric_billing" "crc_google_secondary" {
  provider   = packetfabric
  count      = var.module_enabled ? (var.google_cloud_router_connections.redundant == true ? 1 : 0) : 0
  circuit_id = packetfabric_cloud_router_connection_google.crc_google_secondary[0].id
  depends_on = [time_sleep.delay2]
}

output "cloud_router_connection_google_primary" {
  value = packetfabric_cloud_router_connection_google.crc_google_primary
}

output "cloud_router_connection_google_secondary" {
  value = packetfabric_cloud_router_connection_google.crc_google_secondary
}

output "google_crc_primary_billing" {
  description = "Billing information for the primary Google Cloud Router Connection"
  value       = try(data.packetfabric_billing.crc_google_primary[0].billings, [])
}

output "google_crc_secondary_billing" {
  description = "Billing information for the secondary Google Cloud Router Connection (if created)"
  value       = try(data.packetfabric_billing.crc_google_secondary[0].billings, [])
}
