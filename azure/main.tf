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
  count               = length(coalesce(var.azure_cloud_router_connections, []))
  name                = var.azure_cloud_router_connections[count.index].azure_vnet
  resource_group_name = var.azure_cloud_router_connections[count.index].azure_resource_group
}

# Get the prefixes of the subnets
locals {
  azure_in_prefixes = {
    for index in range(length(coalesce(var.azure_cloud_router_connections, []))) : "${index}-${data.azurerm_virtual_network.vnet[index].id}" => {
      prefix = data.azurerm_virtual_network.vnet[index].address_space[0]
      region = var.azure_cloud_router_connections[index].azure_region
    }
  }
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
  count                 = length(coalesce(var.azure_cloud_router_connections, []))
  name                  = var.azure_cloud_router_connections[count.index].name
  resource_group_name   = var.azure_cloud_router_connections[count.index].azure_resource_group
  location              = var.azure_cloud_router_connections[count.index].azure_region
  peering_location      = var.azure_cloud_router_connections[count.index].azure_pop
  service_provider_name = var.azure_cloud_router_connections[count.index].provider != null ? var.azure_cloud_router_connections.provider : "PacketFabric"
  bandwidth_in_mbps     = local.speed_map[var.azure_cloud_router_connections[count.index].azure_speed]
  sku {
    tier   = var.azure_sku_tier
    family = var.azure_sku_family
  }
  tags = {
    environment = "${var.azure_cloud_router_connections[count.index].name != null ? var.azure_cloud_router_connections[count.index].name : var.name}"
  }
}

# PacketFabric AWS Cloud Router Connection(s)
resource "packetfabric_cloud_router_connection_azure" "crc_azure_primary" {
  provider          = packetfabric
  count             = length(coalesce(var.azure_cloud_router_connections, []))
  description       = "${var.azure_cloud_router_connections[count.index].name}-primary"
  labels            = length(coalesce(var.azure_cloud_router_connections[count.index].labels, var.labels, [])) > 0 ? var.azure_cloud_router_connections[count.index].labels : var.labels
  circuit_id        = var.cr_id
  azure_service_key = azurerm_express_route_circuit.azure_express_route[count.index].service_key
  speed             = coalesce(var.azure_cloud_router_connections[count.index].azure_speed, "1Gbps")
}

locals {
  # Generate list of primary and secondary IP addresses
  ip_addresses = [
    for i in range(length(coalesce(var.azure_cloud_router_connections, []))) : {
      primary   = "169.254.${244 + i}.40/30"
      secondary = "169.254.${244 + i}.44/30"
    }
  ]
}

resource "azurerm_express_route_circuit_peering" "private_circuity" {
  provider                      = azurerm
  count                         = length(coalesce(var.azure_cloud_router_connections, []))
  peering_type                  = "AzurePrivatePeering"
  express_route_circuit_name    = azurerm_express_route_circuit.azure_express_route[count.index].name
  resource_group_name           = var.azure_cloud_router_connections[count.index].azure_resource_group
  peer_asn                      = var.cr_asn
  primary_peer_address_prefix   = local.ip_addresses[count.index].primary
  secondary_peer_address_prefix = local.ip_addresses[count.index].secondary
  vlan_id                       = packetfabric_cloud_router_connection_azure.crc_azure_primary[count.index].vlan_id_private
  # depends_on = [
  #   azurerm_virtual_network_gateway[count.index].vng
  # ]
}

resource "packetfabric_cloud_router_bgp_session" "bgp_azure_primary" {
  provider       = packetfabric
  count          = length(coalesce(var.azure_cloud_router_connections, []))
  circuit_id     = var.cr_id
  connection_id  = packetfabric_cloud_router_connection_azure.crc_azure_primary[count.index].id
  remote_asn     = 12076
  primary_subnet = local.ip_addresses[count.index].primary
  # # Primary - Set AS Prepend to 1 and Local Pref to 10 to prioritized traffic to the primary
  # as_prepend       = 1
  # local_preference = 10
  # OUT: Allowed Prefixes to Cloud (to Azure)
  dynamic "prefixes" {
    for_each = (
      (
        length(var.aws_in_prefixes) == 0 &&
        length(coalesce(var.aws_cloud_router_connections, [])[*].bgp_prefixes[count.index] == null ? [] : var.aws_cloud_router_connections[*].bgp_prefixes[count.index]) == 0
      )
      && (
        length(var.google_in_prefixes) == 0 &&
        length(coalesce(var.google_cloud_router_connections, [])[*].bgp_prefixes[count.index] == null ? [] : var.google_cloud_router_connections[*].bgp_prefixes[count.index]) == 0
      )
      ) ? ["0.0.0.0/0"] : toset(concat(
        [for prefix in var.aws_in_prefixes : prefix.prefix],
        [for prefix in var.google_in_prefixes : prefix.prefix],
        length(coalesce(var.azure_cloud_router_connections[count.index].bgp_prefixes, [])) > 0 ? [for prefix in var.azure_cloud_router_connections[count.index].bgp_prefixes : prefix.prefix if prefix.type == "out"] : []
    ))
    content {
      prefix     = prefixes.value
      type       = "out"
      match_type = coalesce(var.azure_cloud_router_connections[count.index].bgp_prefixes_match_type, "exact")
    }
  }
  # IN: Allowed Prefixes from Cloud (from Azure)
  dynamic "prefixes" {
    for_each = toset(concat(
      [for key, value in local.azure_in_prefixes : value.prefix if value.region == var.azure_cloud_router_connections[count.index].azure_region],
      length(coalesce(var.azure_cloud_router_connections[count.index].bgp_prefixes, [])) > 0 ? [for prefix in var.azure_cloud_router_connections[count.index].bgp_prefixes : prefix.prefix if prefix.type == "in"] : []
    ))
    content {
      prefix     = prefixes.value
      type       = "in"
      match_type = coalesce(var.azure_cloud_router_connections[count.index].bgp_prefixes_match_type, "exact")
    }
  }
}

# Create the redundant connection if redundant set to true
resource "packetfabric_cloud_router_connection_azure" "crc_azure_secondary" {
  provider = packetfabric
  for_each = {
    for idx, connection in coalesce(var.azure_cloud_router_connections, []) : idx => connection if connection.redundant == true
  }
  description       = "${each.value.name}-secondary"
  labels            = each.value.labels != null ? each.value.labels : var.labels
  circuit_id        = var.cr_id
  speed             = each.value.azure_speed != null ? each.value.azure_speed : "1Gbps"
  azure_service_key = azurerm_express_route_circuit.azure_express_route[0].service_key
}

resource "packetfabric_cloud_router_bgp_session" "bgp_azure_secondary" {
  provider = packetfabric
  for_each = {
    for idx, connection in coalesce(var.azure_cloud_router_connections, []) : idx => connection if connection.redundant == true
  }
  circuit_id       = var.cr_id
  connection_id    = packetfabric_cloud_router_connection_azure.crc_azure_secondary[each.key].id
  remote_asn       = 12076
  secondary_subnet = local.ip_addresses[each.key].secondary
  # # Secondary - Set AS Prepend to 5 and Local Pref to 1 to prioritized traffic to the primary
  # as_prepend       = 5
  # local_preference = 1
  # OUT: Allowed Prefixes to Cloud (to Azure)
  dynamic "prefixes" {
    for_each = (
      (
        length(var.aws_in_prefixes) == 0 &&
        length(coalesce(var.aws_cloud_router_connections, [])[*].bgp_prefixes[each.key] == null ? [] : var.aws_cloud_router_connections[*].bgp_prefixes[each.key]) == 0
      )
      && (
        length(var.google_in_prefixes) == 0 &&
        length(coalesce(var.google_cloud_router_connections, [])[*].bgp_prefixes[each.key] == null ? [] : var.google_cloud_router_connections[*].bgp_prefixes[each.key]) == 0
      )
      ) ? ["0.0.0.0/0"] : toset(concat(
        [for prefix in var.aws_in_prefixes : prefix.prefix],
        [for prefix in var.google_in_prefixes : prefix.prefix],
        length(coalesce(each.value.bgp_prefixes, [])) > 0 ? [for prefix in each.value.bgp_prefixes : prefix.prefix if prefix.type == "out"] : []
    ))
    content {
      prefix     = prefixes.value
      type       = "out"
      match_type = coalesce(each.value.bgp_prefixes_match_type, "exact")
    }
  }
  # IN: Allowed Prefixes from Cloud (from Azure)
  dynamic "prefixes" {
    for_each = toset(concat(
      [for key, value in local.azure_in_prefixes : value.prefix if value.region == var.azure_cloud_router_connections[each.key].azure_region],
      length(coalesce(each.value.bgp_prefixes, [])) > 0 ? [for prefix in each.value.bgp_prefixes : prefix.prefix if prefix.type == "in"] : []
    ))
    content {
      prefix     = prefixes.value
      type       = "in"
      match_type = coalesce(each.value.bgp_prefixes_match_type, "exact")
    }
  }
}

# # From the Microsoft side: Create a virtual network gateway for ExpressRoute.
# resource "azurerm_public_ip" "public_ip_vng" {
#   provider            = azurerm
#   count               = var.module_enabled ? (var.azure_cloud_router_connections.skip_gateway != true ? 1 : 0) : 0
#   name                = var.azure_cloud_router_connections.name != null ? var.azure_cloud_router_connections.name : var.name
#   location            = var.azure_cloud_router_connections.azure_region
#   resource_group_name = var.azure_cloud_router_connections.azure_resource_group
#   allocation_method   = "Static"
#   sku                 = "Standard"
#   tags = {
#     environment = "${var.azure_cloud_router_connections.name != null ? var.azure_cloud_router_connections.name : var.name}"
#   }
# }

# # Please be aware that provisioning a Virtual Network Gateway takes a long time (between 30 minutes and 1 hour)
# # Deletion can take up to 15 minutes
# resource "azurerm_virtual_network_gateway" "vng" {
#   provider            = azurerm
#   count               = var.module_enabled ? (var.azure_cloud_router_connections.skip_gateway != true ? 1 : 0) : 0
#   name                = var.azure_cloud_router_connections.name != null ? var.azure_cloud_router_connections.name : var.name
#   location            = var.azure_cloud_router_connections.azure_region
#   resource_group_name = var.azure_cloud_router_connections.azure_resource_group
#   type                = "ExpressRoute"
#   sku                 = "Standard"
#   ip_configuration {
#     name                          = "vnetGatewayConfig"
#     public_ip_address_id          = azurerm_public_ip.public_ip_vng[0].id
#     private_ip_address_allocation = "Dynamic"
#     subnet_id                     = "/subscriptions/${var.azure_cloud_router_connections.azure_subscription_id}/resourceGroups/${var.azure_cloud_router_connections.azure_resource_group}/providers/Microsoft.Network/virtualNetworks/${var.azure_cloud_router_connections.azure_vnet}/subnets/GatewaySubnet"
#   }
#   tags = {
#     environment = "${var.azure_cloud_router_connections.name != null ? var.azure_cloud_router_connections.name : var.name}"
#   }
# }

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

output "cloud_router_connection_azure_primary" {
  value       = packetfabric_cloud_router_connection_azure.crc_azure_primary
  description = "Primary PacketFabric Azure Cloud Router Connection"
}

output "cloud_router_connection_azure_secondary" {
  value       = packetfabric_cloud_router_connection_azure.crc_azure_secondary
  description = "Secondary PacketFabric Azure Cloud Router Connection (if redundant is true)"
}
