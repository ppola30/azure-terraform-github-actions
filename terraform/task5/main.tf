terraform {
  backend "azurerm" {
    resource_group_name  = "tfstate-rg"
    storage_account_name = "pavantfstate23561"
    container_name       = "tfstate"
    key                  = "task5.tfstate"
  }
}

provider "azurerm" {
  features {}
}

data "azurerm_resource_group" "rg" {
  name = "pavan-task1-github-rg"
}

resource "azurerm_virtual_network" "vnet" {
  name                = "task5-vnet"
  location            = data.azurerm_resource_group.rg.location
  resource_group_name = data.azurerm_resource_group.rg.name
  address_space       = ["10.5.0.0/16"]
}

resource "azurerm_subnet" "subnet" {
  name                 = "task5-subnet"
  resource_group_name  = data.azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.5.1.0/24"]
}

resource "azurerm_public_ip" "pip" {
  name                = "task5-public-ip"
  location            = data.azurerm_resource_group.rg.location
  resource_group_name = data.azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_network_security_group" "nsg" {
  name                = "task5-nsg"
  location            = data.azurerm_resource_group.rg.location
  resource_group_name = data.azurerm_resource_group.rg.name
}

resource "azurerm_network_security_rule" "ssh" {
  name                        = "Allow-SSH"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "22"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = data.azurerm_resource_group.rg.name
  network_security_group_name = azurerm_network_security_group.nsg.name
}

resource "azurerm_network_interface" "nic" {
  name                = "task5-nic"
  location            = data.azurerm_resource_group.rg.location
  resource_group_name = data.azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.pip.id
  }
}

resource "azurerm_network_interface_security_group_association" "nsg_assoc" {
  network_interface_id      = azurerm_network_interface.nic.id
  network_security_group_id = azurerm_network_security_group.nsg.id
}

resource "azurerm_linux_virtual_machine" "vm" {
  name                            = "task5-alert-vm"
  resource_group_name             = data.azurerm_resource_group.rg.name
  location                        = data.azurerm_resource_group.rg.location
  size                            = "Standard_B1s"
  admin_username                  = "azureuser"
  admin_password                  = "Pavan@12345"
  disable_password_authentication = false

  network_interface_ids = [
    azurerm_network_interface.nic.id
  ]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
    disk_size_gb         = 30
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }

  custom_data = base64encode(<<EOF
#!/bin/bash
apt-get update -y
apt-get install -y stress-ng stress -y
EOF
  )
}

resource "azurerm_monitor_action_group" "action_group" {
  name                = "task5-action-group"
  resource_group_name = data.azurerm_resource_group.rg.name
  short_name          = "task5ag"

  email_receiver {
    name          = "pavan-email"
    email_address = "ppola@pgsnsofttech.com"
  }
}

# CPU 75 Warning
resource "azurerm_monitor_metric_alert" "cpu_warning" {
  name                = "task5-cpu-warning-75"
  resource_group_name = data.azurerm_resource_group.rg.name
  scopes              = [azurerm_linux_virtual_machine.vm.id]
  severity            = 2
  frequency           = "PT1M"
  window_size         = "PT5M"
  description         = "Warning alert when CPU reaches 75%"

  criteria {
    metric_namespace = "Microsoft.Compute/virtualMachines"
    metric_name      = "Percentage CPU"
    aggregation      = "Average"
    operator         = "GreaterThanOrEqual"
    threshold        = 75
  }

  action {
    action_group_id = azurerm_monitor_action_group.action_group.id
  }
}

# CPU 90 Critical
resource "azurerm_monitor_metric_alert" "cpu_critical" {
  name                = "task5-cpu-critical-90"
  resource_group_name = data.azurerm_resource_group.rg.name
  scopes              = [azurerm_linux_virtual_machine.vm.id]
  severity            = 0
  frequency           = "PT1M"
  window_size         = "PT5M"
  description         = "Critical alert when CPU reaches 90%"

  criteria {
    metric_namespace = "Microsoft.Compute/virtualMachines"
    metric_name      = "Percentage CPU"
    aggregation      = "Average"
    operator         = "GreaterThanOrEqual"
    threshold        = 90
  }

  action {
    action_group_id = azurerm_monitor_action_group.action_group.id
  }
}

# Memory Warning
resource "azurerm_monitor_metric_alert" "memory_warning" {
  name                = "task5-memory-warning-75"
  resource_group_name = data.azurerm_resource_group.rg.name
  scopes              = [azurerm_linux_virtual_machine.vm.id]
  severity            = 2
  frequency           = "PT1M"
  window_size         = "PT5M"
  description         = "Warning alert when available memory is low"

  criteria {
    metric_namespace = "Microsoft.Compute/virtualMachines"
    metric_name      = "Available Memory Bytes"
    aggregation      = "Average"
    operator         = "LessThan"
    threshold        = 300000000
  }

  action {
    action_group_id = azurerm_monitor_action_group.action_group.id
  }
}

# Memory Critical
resource "azurerm_monitor_metric_alert" "memory_critical" {
  name                = "task5-memory-critical-90"
  resource_group_name = data.azurerm_resource_group.rg.name
  scopes              = [azurerm_linux_virtual_machine.vm.id]
  severity            = 0
  frequency           = "PT1M"
  window_size         = "PT5M"
  description         = "Critical alert when available memory is very low"

  criteria {
    metric_namespace = "Microsoft.Compute/virtualMachines"
    metric_name      = "Available Memory Bytes"
    aggregation      = "Average"
    operator         = "LessThan"
    threshold        = 150000000
  }

  action {
    action_group_id = azurerm_monitor_action_group.action_group.id
  }
}

# Disk Warning
resource "azurerm_monitor_metric_alert" "disk_warning" {
  name                = "task5-disk-warning-75"
  resource_group_name = data.azurerm_resource_group.rg.name
  scopes              = [azurerm_linux_virtual_machine.vm.id]
  severity            = 2
  frequency           = "PT1M"
  window_size         = "PT5M"
  description         = "Warning alert when OS disk queue depth is high"

  criteria {
    metric_namespace = "Microsoft.Compute/virtualMachines"
    metric_name      = "OS Disk Queue Depth"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 3
  }

  action {
    action_group_id = azurerm_monitor_action_group.action_group.id
  }
}

# Disk Critical
resource "azurerm_monitor_metric_alert" "disk_critical" {
  name                = "task5-disk-critical-90"
  resource_group_name = data.azurerm_resource_group.rg.name
  scopes              = [azurerm_linux_virtual_machine.vm.id]
  severity            = 0
  frequency           = "PT1M"
  window_size         = "PT5M"
  description         = "Critical alert when OS disk queue depth is very high"

  criteria {
    metric_namespace = "Microsoft.Compute/virtualMachines"
    metric_name      = "OS Disk Queue Depth"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 5
  }

  action {
    action_group_id = azurerm_monitor_action_group.action_group.id
  }
}

output "task5_vm_public_ip" {
  value = azurerm_public_ip.pip.ip_address
}