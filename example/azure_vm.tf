resource "azurerm_network_security_group" "security_group" {
  provider            = azurerm
  name                = "${random_pet.name.id}-sg1"
  location            = var.azure_region
  resource_group_name = azurerm_resource_group.resource_group.name
  security_rule {
    name                       = "SSH"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = var.my_ip
    destination_address_prefix = "*"
  }
  security_rule {
    name                       = "ICMP"
    priority                   = 1002
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Icmp"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
  security_rule {
    name                       = "Nginx"
    priority                   = 1003
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
  security_rule {
    name                       = "Locust"
    priority                   = 1004
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "8089"
    source_address_prefix      = var.my_ip
    destination_address_prefix = "*"
  }
  tags = {
    environment = "${random_pet.name.id}"
  }
}

resource "azurerm_public_ip" "public_ip_vm" {
  provider            = azurerm
  name                = "${random_pet.name.id}-public-ip-vm"
  location            = var.azure_region
  resource_group_name = azurerm_resource_group.resource_group.name
  allocation_method   = "Dynamic"
  tags = {
    environment = "${random_pet.name.id}"
  }
}

resource "azurerm_network_interface" "nic" {
  provider            = azurerm
  name                = "${random_pet.name.id}-nic1"
  location            = var.azure_region
  resource_group_name = azurerm_resource_group.resource_group.name

  ip_configuration {
    name                          = random_pet.name.id
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.public_ip_vm.id
  }
  tags = {
    environment = "${random_pet.name.id}"
  }
}

resource "azurerm_network_interface_security_group_association" "association" {
  provider                  = azurerm
  network_interface_id      = azurerm_network_interface.nic.id
  network_security_group_id = azurerm_network_security_group.security_group.id
}

resource "azurerm_ssh_public_key" "ssh_public_key" {
  provider            = azurerm
  name                = "${random_pet.name.id}-sshkey"
  location            = var.azure_region
  resource_group_name = azurerm_resource_group.resource_group.name
  public_key          = var.public_key
}

resource "azurerm_virtual_machine" "vm" {
  provider                         = azurerm
  name                             = "${random_pet.name.id}-vm1"
  location                         = var.azure_region
  resource_group_name              = azurerm_resource_group.resource_group.name
  network_interface_ids            = [azurerm_network_interface.nic.id]
  vm_size                          = "Standard_DS1_v2"
  delete_os_disk_on_termination    = true
  delete_data_disks_on_termination = true

  storage_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }
  storage_os_disk {
    name              = "${random_pet.name.id}-disk"
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Standard_LRS"
  }
  os_profile {
    computer_name  = "${random_pet.name.id}-azure"
    admin_username = "ubuntu"
    custom_data    = file("./user-data-ubuntu.sh")
  }
  os_profile_linux_config {
    disable_password_authentication = true
    ssh_keys {
      key_data = azurerm_ssh_public_key.ssh_public_key.public_key
      path     = "/home/ubuntu/.ssh/authorized_keys"
    }
  }
  depends_on = [
    # shouldn't be needed but it sounds like Azure TF doesn't track the dependency properly
    azurerm_network_interface.nic,
    azurerm_network_interface_security_group_association.association
  ]
  tags = {
    environment = "${random_pet.name.id}"
  }
}

data "azurerm_network_interface" "nic" {
  provider            = azurerm
  name                = "${random_pet.name.id}-nic1"
  resource_group_name = azurerm_resource_group.resource_group.name
  depends_on = [
    azurerm_virtual_machine.vm,
    azurerm_public_ip.public_ip_vm,
    azurerm_network_interface_security_group_association.association
  ]
}
output "private_ip_vm" {
  description = "Private ip address for VM for Region 1"
  value       = data.azurerm_network_interface.nic.private_ip_address
}

data "azurerm_public_ip" "public_ip_vm" {
  provider            = azurerm
  name                = "${random_pet.name.id}-public-ip-vm"
  resource_group_name = azurerm_resource_group.resource_group.name
  depends_on = [
    azurerm_virtual_machine.vm
  ]
}
output "azure_public_ip_vm" {
  description = "Public ip address for VM (ssh user: ubuntu)"
  value       = data.azurerm_public_ip.public_ip_vm.ip_address
}
