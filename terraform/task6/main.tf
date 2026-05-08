terraform {
  backend "azurerm" {
    resource_group_name  = "tfstate-rg"
    storage_account_name = "pavantfstate23561"
    container_name       = "tfstate"
    key                  = "task6.tfstate"
  }
}

provider "azurerm" {
  features {}
}

data "azurerm_resource_group" "rg" {
  name = "pavan-task1-github-rg"
}

# -----------------------------
# Virtual Network
# -----------------------------

resource "azurerm_virtual_network" "vnet" {
  name                = "task6-vnet"
  address_space       = ["10.6.0.0/16"]
  location            = data.azurerm_resource_group.rg.location
  resource_group_name = data.azurerm_resource_group.rg.name
}

# -----------------------------
# Public Subnet
# -----------------------------

resource "azurerm_subnet" "public_subnet" {
  name                 = "public-subnet"
  resource_group_name  = data.azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.6.1.0/24"]
}

# -----------------------------
# Private Subnet
# -----------------------------

resource "azurerm_subnet" "private_subnet" {
  name                 = "private-subnet"
  resource_group_name  = data.azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.6.2.0/24"]
}

# -----------------------------
# NSG
# -----------------------------

resource "azurerm_network_security_group" "nsg" {
  name                = "task6-nsg"
  location            = data.azurerm_resource_group.rg.location
  resource_group_name = data.azurerm_resource_group.rg.name

  security_rule {
    name                       = "Allow-SSH"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

# -----------------------------
# Public IP
# -----------------------------

resource "azurerm_public_ip" "public_ip" {
  name                = "task6-public-ip"
  location            = data.azurerm_resource_group.rg.location
  resource_group_name = data.azurerm_resource_group.rg.name
  allocation_method   = "Static"
}

# -----------------------------
# Public VM NIC
# -----------------------------

resource "azurerm_network_interface" "public_nic" {
  name                = "task6-public-nic"
  location            = data.azurerm_resource_group.rg.location
  resource_group_name = data.azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.public_subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.public_ip.id
  }
}

# -----------------------------
# Private VM NIC
# -----------------------------

resource "azurerm_network_interface" "private_nic" {
  name                = "task6-private-nic"
  location            = data.azurerm_resource_group.rg.location
  resource_group_name = data.azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.private_subnet.id
    private_ip_address_allocation = "Dynamic"
  }
}

# -----------------------------
# NSG Association
# -----------------------------

resource "azurerm_network_interface_security_group_association" "public_assoc" {
  network_interface_id      = azurerm_network_interface.public_nic.id
  network_security_group_id = azurerm_network_security_group.nsg.id
}

resource "azurerm_network_interface_security_group_association" "private_assoc" {
  network_interface_id      = azurerm_network_interface.private_nic.id
  network_security_group_id = azurerm_network_security_group.nsg.id
}

# -----------------------------
# Public VM
# -----------------------------

resource "azurerm_linux_virtual_machine" "public_vm" {
  name                            = "task6-public-vm"
  resource_group_name             = data.azurerm_resource_group.rg.name
  location                        = data.azurerm_resource_group.rg.location
  size                            = "Standard_B1s"
  admin_username                  = "azureuser"
  admin_password                  = "Pavan@12345"
  disable_password_authentication = false

  network_interface_ids = [
    azurerm_network_interface.public_nic.id
  ]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }
}

# -----------------------------
# Private VM
# -----------------------------

resource "azurerm_linux_virtual_machine" "private_vm" {
  name                            = "task6-private-vm"
  resource_group_name             = data.azurerm_resource_group.rg.name
  location                        = data.azurerm_resource_group.rg.location
  size                            = "Standard_B1s"
  admin_username                  = "azureuser"
  admin_password                  = "Pavan@12345"
  disable_password_authentication = false

  network_interface_ids = [
    azurerm_network_interface.private_nic.id
  ]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }
}

# -----------------------------
# Outputs
# -----------------------------

output "public_vm_ip" {
  value = azurerm_public_ip.public_ip.ip_address
}