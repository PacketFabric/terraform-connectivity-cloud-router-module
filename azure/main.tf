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

provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}

# Get the network prefix from the Azure VNet
data "azurerm_virtual_network" "vnet" {
  count               = var.module_enabled ? 1 : 0
  name                = var.azure_cloud_router_connections.azure_vnet
  resource_group_name = var.azure_cloud_router_connections.azure_resource_group
}

locals {
  # Get the prefixes of the subnets
  azure_in_prefixes = var.azure_cloud_router_connections != null ? {
    "vpc_cidr" = {
      prefix = data.azurerm_virtual_network.vnet[0].address_space[0]
    }
  } : {}
}

output "azure_in_prefixes" {
  value = local.azure_in_prefixes
}

locals {
  speed_map = {
    "50Mbps"  = 50
    "100Mbps" = 100
    "200Mbps" = 200
    "300Mbps" = 300
    "400Mbps" = 400
    "500Mbps" = 500
    "1Gbps"   = 1000
    "2Gbps"   = 2000
    "5Gbps"   = 5000
    "10Gbps"  = 10000
  }
}

resource "azurerm_express_route_circuit" "azure_express_route" {
  provider              = azurerm
  count                 = var.module_enabled ? 1 : 0
  name                  = var.azure_cloud_router_connections.name != null ? var.azure_cloud_router_connections.name : var.name
  resource_group_name   = var.azure_cloud_router_connections.azure_resource_group
  location              = var.azure_cloud_router_connections.azure_region
  peering_location      = var.azure_cloud_router_connections.azure_pop
  service_provider_name = var.azure_cloud_router_connections.provider != null ? var.azure_cloud_router_connections.provider : "PacketFabric"
  bandwidth_in_mbps     = local.speed_map[var.azure_cloud_router_connections.azure_speed]
  sku {
    tier   = var.azure_sku_tier
    family = var.azure_sku_family
  }
  tags = {
    environment = "${var.azure_cloud_router_connections.name != null ? var.azure_cloud_router_connections.name : var.name}"
  }
}

# PacketFabric AWS Cloud Router Connection(s)
resource "packetfabric_cloud_router_connection_azure" "crc_azure_primary" {
  provider          = packetfabric
  count             = var.module_enabled ? 1 : 0
  description       = "${var.azure_cloud_router_connections.name != null ? var.azure_cloud_router_connections.name : var.name}-primary"
  labels            = var.azure_cloud_router_connections.labels != null ? var.azure_cloud_router_connections.labels : var.labels
  circuit_id        = var.cr_id
  azure_service_key = azurerm_express_route_circuit.azure_express_route[0].service_key
  speed             = var.azure_cloud_router_connections.azure_speed != null ? var.azure_cloud_router_connections.azure_speed : "1Gbps"
}

resource "azurerm_express_route_circuit_peering" "private_circuity" {
  provider                      = azurerm
  count                         = var.module_enabled ? 1 : 0
  peering_type                  = "AzurePrivatePeering"
  express_route_circuit_name    = azurerm_express_route_circuit.azure_express_route[0].name
  resource_group_name           = var.azure_cloud_router_connections.azure_resource_group
  peer_asn                      = var.cr_asn
  primary_peer_address_prefix   = var.azure_primary_peer_address_prefix
  secondary_peer_address_prefix = var.azure_secondary_peer_address_prefix
  vlan_id                       = packetfabric_cloud_router_connection_azure.crc_azure_primary[0].vlan_id_private
  depends_on = [
    azurerm_virtual_network_gateway.vng[0]
  ]
}

resource "packetfabric_cloud_router_bgp_session" "bgp_azure_primary" {
  provider       = packetfabric
  count          = var.module_enabled ? 1 : 0
  circuit_id     = var.cr_id
  connection_id  = packetfabric_cloud_router_connection_azure.crc_azure_primary[0].id
  remote_asn     = 12076
  primary_subnet = var.azure_primary_peer_address_prefix
  # # Primary - Set AS Prepend to 1 and Local Pref to 10 to prioritized traffic to the primary
  # as_prepend       = 1
  # local_preference = 10
  # OUT: Allowed Prefixes to Cloud (to AWS)
  dynamic "prefixes" {
    for_each = (
      (length(var.google_in_prefixes) == 0 &&
      length(try(coalesce(var.google_cloud_router_connections.bgp_prefixes, []), [])) == 0) &&
      (length(var.aws_in_prefixes) == 0 &&
      length(try(coalesce(var.aws_cloud_router_connections.bgp_prefixes, []), [])) == 0)
      ) ? ["0.0.0.0/0"] : toset(concat(
        [for prefix in var.google_in_prefixes : prefix.prefix],
        [for prefix in var.aws_in_prefixes : prefix.prefix],
        var.azure_cloud_router_connections.bgp_prefixes != null ? [for prefix in var.azure_cloud_router_connections.bgp_prefixes : prefix.prefix if prefix.type == "out"] : []
    ))
    content {
      prefix     = prefixes.value
      type       = "out"
      match_type = var.azure_cloud_router_connections.bgp_prefixes_match_type != null ? var.azure_cloud_router_connections.bgp_prefixes_match_type : "exact"
    }
  }
  # IN: Allowed Prefixes from Cloud (from AWS)
  dynamic "prefixes" {
    for_each = toset(concat(
      [for prefix in local.azure_in_prefixes : prefix.prefix],
      var.azure_cloud_router_connections.bgp_prefixes != null ? [for prefix in var.azure_cloud_router_connections.bgp_prefixes : prefix.prefix if prefix.type == "in"] : []
    ))
    content {
      prefix     = prefixes.value
      type       = "in"
      match_type = var.azure_cloud_router_connections.bgp_prefixes_match_type != null ? var.azure_cloud_router_connections.bgp_prefixes_match_type : "exact"
    }
  }
}

# Wait 30s before getting the billing information
resource "time_sleep" "delay1" {
  count           = var.module_enabled ? 1 : 0
  depends_on      = [packetfabric_cloud_router_connection_azure.crc_azure_primary[0]]
  create_duration = "30s"
}

data "packetfabric_billing" "crc_azure_primary" {
  provider   = packetfabric
  count      = var.module_enabled ? 1 : 0
  circuit_id = packetfabric_cloud_router_connection_azure.crc_azure_primary[0].id
  depends_on = [time_sleep.delay1]
}

# Create the redundant connection if redundant set to true
resource "packetfabric_cloud_router_connection_azure" "crc_azure_secondary" {
  provider          = packetfabric
  count             = var.module_enabled ? (var.azure_cloud_router_connections.redundant == true ? 1 : 0) : 0
  description       = "${var.azure_cloud_router_connections.name != null ? var.azure_cloud_router_connections.name : var.name}-secondary"
  labels            = var.azure_cloud_router_connections.labels != null ? var.azure_cloud_router_connections.labels : var.labels
  circuit_id        = var.cr_id
  speed             = var.azure_cloud_router_connections.azure_speed != null ? var.azure_cloud_router_connections.azure_speed : "1Gbps"
  azure_service_key = azurerm_express_route_circuit.azure_express_route[0].service_key
  # Create one connection at a time, especially for update
  depends_on = [
    packetfabric_cloud_router_connection_azure.crc_azure_primary[0]
  ]
}

resource "packetfabric_cloud_router_bgp_session" "bgp_azure_secondary" {
  provider         = packetfabric
  count            = var.module_enabled ? (var.azure_cloud_router_connections.redundant == true ? 1 : 0) : 0
  circuit_id       = var.cr_id
  connection_id    = packetfabric_cloud_router_connection_azure.crc_azure_secondary[0].id
  remote_asn       = 12076
  secondary_subnet = var.azure_secondary_peer_address_prefix
  # # Secondary - Set AS Prepend to 5 and Local Pref to 1 to prioritized traffic to the primary
  # as_prepend       = 5
  # local_preference = 1
  # OUT: Allowed Prefixes to Cloud (to AWS)
  dynamic "prefixes" {
    for_each = (
      (length(var.google_in_prefixes) == 0 &&
      length(try(coalesce(var.google_cloud_router_connections.bgp_prefixes, []), [])) == 0) &&
      (length(var.aws_in_prefixes) == 0 &&
      length(try(coalesce(var.aws_cloud_router_connections.bgp_prefixes, []), [])) == 0)
      ) ? ["0.0.0.0/0"] : toset(concat(
        [for prefix in var.google_in_prefixes : prefix.prefix],
        [for prefix in var.aws_in_prefixes : prefix.prefix],
        var.azure_cloud_router_connections.bgp_prefixes != null ? [for prefix in var.azure_cloud_router_connections.bgp_prefixes : prefix.prefix if prefix.type == "out"] : []
    ))
    content {
      prefix     = prefixes.value
      type       = "out"
      match_type = var.azure_cloud_router_connections.bgp_prefixes_match_type != null ? var.azure_cloud_router_connections.bgp_prefixes_match_type : "exact"
    }
  }
  # IN: Allowed Prefixes from Cloud (from AWS)
  dynamic "prefixes" {
    for_each = toset(concat(
      [for prefix in local.azure_in_prefixes : prefix.prefix],
      var.azure_cloud_router_connections.bgp_prefixes != null ? [for prefix in var.azure_cloud_router_connections.bgp_prefixes : prefix.prefix if prefix.type == "in"] : []
    ))
    content {
      prefix     = prefixes.value
      type       = "in"
      match_type = var.azure_cloud_router_connections.bgp_prefixes_match_type != null ? var.azure_cloud_router_connections.bgp_prefixes_match_type : "exact"
    }
  }
}

# From the Microsoft side: Create a virtual network gateway for ExpressRoute.
resource "azurerm_public_ip" "public_ip_vng" {
  provider            = azurerm
  count               = var.module_enabled ? (var.azure_cloud_router_connections.skip_gateway != true ? 1 : 0) : 0
  name                = var.azure_cloud_router_connections.name != null ? var.azure_cloud_router_connections.name : var.name
  location            = var.azure_cloud_router_connections.azure_region
  resource_group_name = var.azure_cloud_router_connections.azure_resource_group
  allocation_method   = "Static"
  sku                 = "Standard"
  tags = {
    environment = "${var.azure_cloud_router_connections.name != null ? var.azure_cloud_router_connections.name : var.name}"
  }
}

# Please be aware that provisioning a Virtual Network Gateway takes a long time (between 30 minutes and 1 hour)
# Deletion can take up to 15 minutes
resource "azurerm_virtual_network_gateway" "vng" {
  provider            = azurerm
  count               = var.module_enabled ? (var.azure_cloud_router_connections.skip_gateway != true ? 1 : 0) : 0
  name                = var.azure_cloud_router_connections.name != null ? var.azure_cloud_router_connections.name : var.name
  location            = var.azure_cloud_router_connections.azure_region
  resource_group_name = var.azure_cloud_router_connections.azure_resource_group
  type                = "ExpressRoute"
  sku                 = "Standard"
  ip_configuration {
    name                          = "vnetGatewayConfig"
    public_ip_address_id          = azurerm_public_ip.public_ip_vng[0].id
    private_ip_address_allocation = "Dynamic"
    subnet_id                     = "/subscriptions/${var.azure_cloud_router_connections.azure_subscription_id}/resourceGroups/${var.azure_cloud_router_connections.azure_resource_group}/providers/Microsoft.Network/virtualNetworks/${var.azure_cloud_router_connections.azure_vnet}/subnets/GatewaySubnet"
  }
  tags = {
    environment = "${var.azure_cloud_router_connections.name != null ? var.azure_cloud_router_connections.name : var.name}"
  }
}

# From the Microsoft side: Link a virtual network gateway to the ExpressRoute circuit.
resource "azurerm_virtual_network_gateway_connection" "vng_connection" {
  provider                   = azurerm
  count                      = var.module_enabled ? (var.azure_cloud_router_connections.skip_gateway != true ? 1 : 0) : 0
  name                       = var.azure_cloud_router_connections.name != null ? var.azure_cloud_router_connections.name : var.name
  location                   = var.azure_cloud_router_connections.azure_region
  resource_group_name        = var.azure_cloud_router_connections.azure_resource_group
  type                       = "ExpressRoute"
  express_route_circuit_id   = azurerm_express_route_circuit.azure_express_route[0].id
  virtual_network_gateway_id = azurerm_virtual_network_gateway.vng[0].id
  routing_weight             = 0
  tags = {
    environment = "${var.azure_cloud_router_connections.name != null ? var.azure_cloud_router_connections.name : var.name}"
  }
}

# Wait for the secondary connection to be created before getting billing info
resource "time_sleep" "delay2" {
  count           = var.module_enabled ? (var.azure_cloud_router_connections.redundant == true ? 1 : 0) : 0
  depends_on      = [packetfabric_cloud_router_connection_azure.crc_azure_secondary[0]]
  create_duration = "30s"
}

data "packetfabric_billing" "crc_azure_secondary" {
  provider   = packetfabric
  count      = var.module_enabled ? (var.azure_cloud_router_connections.redundant == true ? 1 : 0) : 0
  circuit_id = packetfabric_cloud_router_connection_azure.crc_azure_secondary[0].id
  depends_on = [time_sleep.delay2]
}

output "cloud_router_connection_azure_primary" {
  value       = packetfabric_cloud_router_connection_azure.crc_azure_primary
  description = "Primary PacketFabric Azure Cloud Router Connection"
}

output "cloud_router_connection_azure_secondary" {
  value       = packetfabric_cloud_router_connection_azure.crc_azure_secondary
  description = "Secondary PacketFabric Azure Cloud Router Connection (if redundant is true)"
}
