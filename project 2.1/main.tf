# main.tf - Core Terraform Configuration for High-Availability Web Infrastructure

# Locals for HTML Base64 pages to prevent shell parsing and escaping errors
locals {
  html_base64 = [
    # Server 1 - Light Blue Theme
    "PGh0bWw+PGJvZHkgc3R5bGU9ImZvbnQtZmFtaWx5OiBBcmlhbCwgc2Fucy1zZXJpZjsgdGV4dC1hbGlnbjogY2VudGVyOyBtYXJnaW4tdG9wOiAxMCU7IGJhY2tncm91bmQtY29sb3I6ICNmMGY4ZmY7Ij48aDE+V2VsY29tZSB0byBTZXJ2ZXIgMTwvaDE+PHA+U2VydmVkIGZyb20gQmFja2VuZCBWTSAxIChIaWdobHkgQXZhaWxhYmxlKTwvcD48L2JvZHk+PC9odG1sPg==",
    # Server 2 - Light Pink Theme
    "PGh0bWw+PGJvZHkgc3R5bGU9ImZvbnQtZmFtaWx5OiBBcmlhbCwgc2Fucy1zZXJpZjsgdGV4dC1hbGlnbjogY2VudGVyOyBtYXJnaW4tdG9wOiAxMCU7IGJhY2tncm91bmQtY29sb3I6ICNmZmU0ZTE7Ij48aDE+V2VsY29tZSB0byBTZXJ2ZXIgMjwvaDE+PHA+U2VydmVkIGZyb20gQmFja2VuZCBWTSAyIChIaWdobHkgQXZhaWxhYmxlKTwvcD48L2JvZHk+PC9odG1sPg=="
  ]
}

# 1. Resource Group
resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location
}

# 2. Availability Set (Redundancy within the datacenter)
resource "azurerm_availability_set" "as" {
  name                         = "as-lb-project-tf"
  resource_group_name          = azurerm_resource_group.main.name
  location                     = azurerm_resource_group.main.location
  platform_fault_domain_count  = 2
  platform_update_domain_count = 2
}

# 3. Virtual Network & Subnet
resource "azurerm_virtual_network" "vnet" {
  name                = "vnet-lb-project-tf"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  address_space       = ["10.0.0.0/16"]
}

resource "azurerm_subnet" "subnet" {
  name                 = "subnet-lb-project-tf"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.1.0/24"]
}

# 4. Network Security Group (NSG) and Rules
resource "azurerm_network_security_group" "nsg" {
  name                = "nsg-lb-project-tf"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location

  security_rule {
    name                       = "Allow-HTTP"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

# Associate NSG with Subnet
resource "azurerm_subnet_network_security_group_association" "nsg_assoc" {
  subnet_id                 = azurerm_subnet.subnet.id
  network_security_group_id = azurerm_network_security_group.nsg.id
}

# 5. Public IP for Load Balancer
resource "azurerm_public_ip" "lb_pip" {
  name                = "pip-lb-project-tf"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = "Standard"
  allocation_method   = "Static"
}

# 6. Load Balancer Configuration
resource "azurerm_lb" "lb" {
  name                = "lb-project-tf"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = "Standard"

  frontend_ip_configuration {
    name                 = "front-ip-config"
    public_ip_address_id = azurerm_public_ip.lb_pip.id
  }
}

# Load Balancer Backend Address Pool
resource "azurerm_lb_backend_address_pool" "backend_pool" {
  name            = "backend-pool"
  loadbalancer_id = azurerm_lb.lb.id
}

# Load Balancer TCP Health Probe for Port 80
resource "azurerm_lb_probe" "hp" {
  name            = "hp-port-80"
  loadbalancer_id = azurerm_lb.lb.id
  port            = 80
  protocol        = "Tcp"
  interval_in_seconds = 15
  number_of_probes    = 2
}

# Load Balancer HTTP Rule
resource "azurerm_lb_rule" "lb_rule" {
  name                           = "lb-rule-http"
  loadbalancer_id                = azurerm_lb.lb.id
  protocol                       = "Tcp"
  frontend_port                  = 80
  backend_port                   = 80
  frontend_ip_configuration_name = "front-ip-config"
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.backend_pool.id]
  probe_id                       = azurerm_lb_probe.hp.id
}

# 7. Network Interfaces for VMs (No Public IPs assigned)
resource "azurerm_network_interface" "vm_nic" {
  count               = 2
  name                = "nic-vm-server-${count.index + 1}-tf"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Dynamic"
  }
}

# Associate NICs with Load Balancer Backend Address Pool
resource "azurerm_network_interface_backend_address_pool_association" "nic_assoc" {
  count                   = 2
  network_interface_id    = azurerm_network_interface.vm_nic[count.index].id
  ip_configuration_name   = "internal"
  backend_address_pool_id = azurerm_lb_backend_address_pool.backend_pool.id
}

# 8. Virtual Machines (Provisioned in Availability Set)
resource "azurerm_windows_virtual_machine" "vm" {
  count               = 2
  name                = "vm-server-${count.index + 1}-tf"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  size                = var.vm_size
  admin_username      = var.admin_username
  admin_password      = var.admin_password
  availability_set_id = azurerm_availability_set.as.id
  network_interface_ids = [
    azurerm_network_interface.vm_nic[count.index].id
  ]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2022-datacenter-smalldisk-g2" # Boot-efficient smaller 30GB disk
    version   = "latest"
  }
}

# 9. Custom Script Extension to Install IIS and Custom Web Page inside VMs
resource "azurerm_virtual_machine_extension" "iis" {
  count                = 2
  name                 = "install-iis"
  virtual_machine_id   = azurerm_windows_virtual_machine.vm[count.index].id
  publisher            = "Microsoft.Compute"
  type                 = "CustomScriptExtension"
  type_handler_version = "1.10"

  settings = <<SETTINGS
    {
      "commandToExecute": "powershell -ExecutionPolicy Unrestricted -Command \"Install-WindowsFeature -name Web-Server -IncludeManagementTools; $html = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String('${local.html_base64[count.index]}')); Set-Content -Path 'C:\\inetpub\\wwwroot\\iisstart.htm' -Value $html\""
    }
  SETTINGS

  depends_on = [
    azurerm_windows_virtual_machine.vm
  ]
}

# 10. Entra ID (Azure AD) Operations Group
resource "azuread_group" "ops_group" {
  display_name     = "ops-team-group-tf"
  mail_nickname    = "opsteamtf"
  security_enabled = true
}

# 11. Role Assignment - Grant Contributor role to Group at Resource Group Scope
resource "azurerm_role_assignment" "ops_role" {
  scope                = azurerm_resource_group.main.id
  role_definition_name = "Contributor"
  principal_id         = azuread_group.ops_group.object_id
}
