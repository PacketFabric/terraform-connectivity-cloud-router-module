resource "azurerm_resource_group" "resource_group" {
  provider = azurerm
  name     = "${random_pet.name.id}"
  location = var.azure_region
}

resource "azurerm_virtual_network" "virtual_network" {
  provider            = azurerm
  name                = "${random_pet.name.id}-vnet"
  location            = azurerm_resource_group.resource_group.location
  resource_group_name = azurerm_resource_group.resource_group.name
  address_space       = ["${var.azure_vnet_cidr}"]
  tags = {
    environment = "${random_pet.name.id}"
  }
}

resource "azurerm_subnet" "subnet" {
  provider             = azurerm
  name                 = "${random_pet.name.id}-subnet"
  address_prefixes     = ["${var.azure_subnet_cidr}"]
  resource_group_name  = azurerm_resource_group.resource_group.name
  virtual_network_name = azurerm_virtual_network.virtual_network.name
}

# Subnet used for the azurerm_virtual_network_gateway only
# https://learn.microsoft.com/en-us/azure/expressroute/expressroute-about-virtual-network-gateways#gwsub
resource "azurerm_subnet" "subnet_gw" {
  provider             = azurerm
  name                 = "GatewaySubnet"
  address_prefixes     = ["${var.azure_subnet_cidr_gw}"]
  resource_group_name  = azurerm_resource_group.resource_group.name
  virtual_network_name = azurerm_virtual_network.virtual_network.name
}