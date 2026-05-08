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
  address_space       = ["10.5.0.0/16"]
  location            = data.azurerm_resource_group.rg.location
  resource_group_name = data.azurerm_resource_group.rg.name
}

resource "azurerm_subnet" "subnet" {
  name                 = "task5-subnet"
  resource_group_name  = data.azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.5.1.0/24"]
}

resource "azurerm_network_security_group" "nsg" {
  name                = "task5-nsg"
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

resource "azurerm_public_ip" "pip" {
  name                = "task5-public-ip"
  location            = data.azurerm_resource_group.rg.location
  resource_group_name = data.azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
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
apt-get install -y stress-ng
EOF
  )
}

resource "azurerm_monitor_action_group" "action_group" {
  name                = "task5-action-group"
  resource_group_name = data.azurerm_resource_group.rg.name
  short_name          = "task5ag"

  email_receiver {
    name          = "email-alert"
    email_address = "ppola@pgsnsofttech.com"
  }
}

resource "azurerm_log_analytics_workspace" "law" {
  name                = "task5-law"
  location            = data.azurerm_resource_group.rg.location
  resource_group_name = data.azurerm_resource_group.rg.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

resource "azurerm_virtual_machine_extension" "ama" {
  name                       = "AzureMonitorLinuxAgent"
  virtual_machine_id         = azurerm_linux_virtual_machine.vm.id
  publisher                  = "Microsoft.Azure.Monitor"
  type                       = "AzureMonitorLinuxAgent"
  type_handler_version       = "1.33"
  auto_upgrade_minor_version = true
}

resource "azurerm_monitor_data_collection_endpoint" "dce" {
  name                = "task5-dce"
  location            = data.azurerm_resource_group.rg.location
  resource_group_name = data.azurerm_resource_group.rg.name
}

resource "azurerm_monitor_data_collection_rule" "dcr" {
  name                        = "task5-dcr"
  location                    = data.azurerm_resource_group.rg.location
  resource_group_name         = data.azurerm_resource_group.rg.name
  data_collection_endpoint_id = azurerm_monitor_data_collection_endpoint.dce.id

  destinations {
    log_analytics {
      workspace_resource_id = azurerm_log_analytics_workspace.law.id
      name                  = "law-destination"
    }
  }

  data_flow {
    streams      = ["Microsoft-InsightsMetrics"]
    destinations = ["law-destination"]
  }

  data_sources {
    performance_counter {
      streams                       = ["Microsoft-InsightsMetrics"]
      sampling_frequency_in_seconds = 60
      counter_specifiers = [
        "\\Memory\\% Committed Bytes In Use",
        "\\LogicalDisk(_Total)\\% Free Space"
      ]
      name = "perfCounters"
    }
  }
}

resource "azurerm_monitor_data_collection_rule_association" "assoc" {
  name                    = "task5-dcr-association"
  target_resource_id      = azurerm_linux_virtual_machine.vm.id
  data_collection_rule_id = azurerm_monitor_data_collection_rule.dcr.id
}

# CPU 75% Warning
resource "azurerm_monitor_metric_alert" "cpu_warning" {
  name                = "task5-cpu-warning-75"
  resource_group_name = data.azurerm_resource_group.rg.name
  scopes              = [azurerm_linux_virtual_machine.vm.id]
  description         = "Warning alert when CPU usage reaches 75%"
  severity            = 2
  frequency           = "PT1M"
  window_size         = "PT5M"

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

# CPU 90% Critical
resource "azurerm_monitor_metric_alert" "cpu_critical" {
  name                = "task5-cpu-critical-90"
  resource_group_name = data.azurerm_resource_group.rg.name
  scopes              = [azurerm_linux_virtual_machine.vm.id]
  description         = "Critical alert when CPU usage reaches 90%"
  severity            = 0
  frequency           = "PT1M"
  window_size         = "PT5M"

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

# Memory 75% Warning
resource "azurerm_monitor_scheduled_query_rules_alert_v2" "memory_warning" {
  name                = "task5-memory-warning-75"
  location            = data.azurerm_resource_group.rg.location
  resource_group_name = data.azurerm_resource_group.rg.name
  scopes              = [azurerm_log_analytics_workspace.law.id]
  description         = "Warning alert when memory usage reaches 75%"
  severity            = 2

  evaluation_frequency = "PT5M"
  window_duration      = "PT5M"

  criteria {
    query = <<-QUERY
InsightsMetrics
| where Namespace == "Memory"
| where Name == "UtilizationPercentage"
| summarize AggregatedValue = avg(Val) by bin(TimeGenerated, 5m)
QUERY

    time_aggregation_method = "Average"
    metric_measure_column   = "AggregatedValue"
    operator                = "GreaterThanOrEqual"
    threshold               = 75
  }

  action {
    action_groups = [azurerm_monitor_action_group.action_group.id]
  }
}

# Memory 90% Critical
resource "azurerm_monitor_scheduled_query_rules_alert_v2" "memory_critical" {
  name                = "task5-memory-critical-90"
  location            = data.azurerm_resource_group.rg.location
  resource_group_name = data.azurerm_resource_group.rg.name
  scopes              = [azurerm_log_analytics_workspace.law.id]
  description         = "Critical alert when memory usage reaches 90%"
  severity            = 0

  evaluation_frequency = "PT5M"
  window_duration      = "PT5M"

  criteria {
    query = <<-QUERY
InsightsMetrics
| where Namespace == "Memory"
| where Name == "UtilizationPercentage"
| summarize AggregatedValue = avg(Val) by bin(TimeGenerated, 5m)
QUERY

    time_aggregation_method = "Average"
    metric_measure_column   = "AggregatedValue"
    operator                = "GreaterThanOrEqual"
    threshold               = 90
  }

  action {
    action_groups = [azurerm_monitor_action_group.action_group.id]
  }
}

# Disk 75% Warning
# Azure collects free space, so 75% used means 25% free space remaining.
resource "azurerm_monitor_scheduled_query_rules_alert_v2" "disk_warning" {
  name                = "task5-disk-warning-75"
  location            = data.azurerm_resource_group.rg.location
  resource_group_name = data.azurerm_resource_group.rg.name
  scopes              = [azurerm_log_analytics_workspace.law.id]
  description         = "Warning alert when disk usage reaches 75%"
  severity            = 2

  evaluation_frequency = "PT5M"
  window_duration      = "PT5M"

  criteria {
    query = <<-QUERY
InsightsMetrics
| where Namespace == "LogicalDisk"
| where Name == "FreeSpacePercentage"
| summarize AggregatedValue = avg(Val) by bin(TimeGenerated, 5m)
QUERY

    time_aggregation_method = "Average"
    metric_measure_column   = "AggregatedValue"
    operator                = "LessThanOrEqual"
    threshold               = 25
  }

  action {
    action_groups = [azurerm_monitor_action_group.action_group.id]
  }
}

# Disk 90% Critical
# Azure collects free space, so 90% used means 10% free space remaining.
resource "azurerm_monitor_scheduled_query_rules_alert_v2" "disk_critical" {
  name                = "task5-disk-critical-90"
  location            = data.azurerm_resource_group.rg.location
  resource_group_name = data.azurerm_resource_group.rg.name
  scopes              = [azurerm_log_analytics_workspace.law.id]
  description         = "Critical alert when disk usage reaches 90%"
  severity            = 0

  evaluation_frequency = "PT5M"
  window_duration      = "PT5M"

  criteria {
    query = <<-QUERY
InsightsMetrics
| where Namespace == "LogicalDisk"
| where Name == "FreeSpacePercentage"
| summarize AggregatedValue = avg(Val) by bin(TimeGenerated, 5m)
QUERY

    time_aggregation_method = "Average"
    metric_measure_column   = "AggregatedValue"
    operator                = "LessThanOrEqual"
    threshold               = 10
  }

  action {
    action_groups = [azurerm_monitor_action_group.action_group.id]
  }
}