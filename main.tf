provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}

provider "azuread" {

}

resource "random_pet" "p" {
  length    = 1
  separator = ""
}

locals {
  resource_name = format("%s%s", "idops", random_pet.p.id)
}

resource "azurerm_resource_group" "aadds" {
  name     = "rg-${local.resource_name}"
  location = var.location
}

resource "azurerm_virtual_network" "aadds" {
  name                = "vn-${local.resource_name}"
  location            = azurerm_resource_group.aadds.location
  resource_group_name = azurerm_resource_group.aadds.name
  address_space       = var.aadds_vnet_prefixes
  dns_servers         = var.aadds_vnet_custom_dns_servers
}

resource "azurerm_subnet" "aadds" {
  name                 = "sn-${local.resource_name}"
  resource_group_name  = azurerm_resource_group.aadds.name
  virtual_network_name = azurerm_virtual_network.aadds.name
  address_prefixes     = var.aadds_subnet_prefixes
}

resource "azurerm_network_security_group" "aadds" {
  name                = "nsg-${local.resource_name}"
  location            = azurerm_resource_group.aadds.location
  resource_group_name = azurerm_resource_group.aadds.name

  security_rule {
    name                       = "AllowSyncWithAzureAD"
    priority                   = 101
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "AzureActiveDirectoryDomainServices"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowRD"
    priority                   = 201
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3389"
    source_address_prefix      = "CorpNetSaw"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowPSRemoting"
    priority                   = 301
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "5986"
    source_address_prefix      = "AzureActiveDirectoryDomainServices"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowLDAPS"
    priority                   = 401
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "636"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "aadds" {
  subnet_id                 = azurerm_subnet.aadds.id
  network_security_group_id = azurerm_network_security_group.aadds.id
}

##############################################
# AZURE VNET PEERING
##############################################

resource "azurerm_virtual_network_peering" "aadds" {
  for_each                     = { for vp in var.vnet_peerings : vp.peering_name => vp }
  name                         = each.value["peering_name"]
  remote_virtual_network_id    = each.value["resource_id"]
  resource_group_name          = azurerm_resource_group.aadds.name
  virtual_network_name         = azurerm_virtual_network.aadds.name # update module to include vnet in its ouput
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = false
  use_remote_gateways          = true
}

#############################################
# ROUTE TABLES
#############################################

resource "azurerm_route_table" "aadds" {
  name                          = "rt-${local.resource_name}"
  resource_group_name           = azurerm_resource_group.aadds.name
  location                      = azurerm_resource_group.aadds.location
  disable_bgp_route_propagation = true
  tags                          = var.tags

  dynamic "route" {
    for_each = var.aadds_subnet_routes
    content {
      name                   = route.value["route_name"]
      address_prefix         = route.value["address_prefix"]
      next_hop_type          = route.value["next_hop_type"]
      next_hop_in_ip_address = route.value["next_hop_ip_address"]
    }
  }
}

resource "azurerm_subnet_route_table_association" "aadds" {
  subnet_id      = azurerm_subnet.aadds.id
  route_table_id = azurerm_route_table.aadds.id
}

#############################################
# AADDS
#############################################

resource "azurerm_active_directory_domain_service" "aadds" {
  name                = "aadds-${local.resource_name}"
  location            = azurerm_resource_group.aadds.location
  resource_group_name = azurerm_resource_group.aadds.name

  domain_name           = var.aadds_domain_name
  sku                   = var.aadds_sku
  filtered_sync_enabled = false

  initial_replica_set {
    subnet_id = azurerm_subnet.aadds.id
  }

  notifications {
    additional_recipients = ["pauyu@microsoft.com"]
    notify_dc_admins      = true
    notify_global_admins  = true
  }

  security {
    sync_kerberos_passwords = true
    sync_ntlm_passwords     = true
    sync_on_prem_passwords  = true
  }

  tags = var.tags

  depends_on = [
    azurerm_subnet_network_security_group_association.aadds,
  ]
}

#############################################
# AADDS MANAGEMENT USER
#############################################

data "azuread_group" "aadds" {
  display_name = "AAD DC Administrators"
}

resource "azuread_user" "aadds" {
  user_principal_name = var.domain_admin_username
  display_name        = "Domain Joiner"
  password            = var.domain_admin_password

  depends_on = [
    azurerm_active_directory_domain_service.aadds
  ]
}

resource "azuread_group_member" "aadds" {
  group_object_id  = data.azuread_group.aadds.object_id
  member_object_id = azuread_user.aadds.object_id
}

# resource "azuread_service_principal" "example" {
#   application_id = "2565bd9d-da50-47d4-8b85-4c97f669dc36" // published app for domain services
# }

#############################################
# AADDS MANAGEMENT VM
#############################################

locals {
  vm_name = substr(format("%s%s", "vm", local.resource_name), 0, 15)
}

resource "azurerm_network_interface" "aadds" {
  name                = "${local.vm_name}-1_nic"
  resource_group_name = azurerm_resource_group.aadds.name
  location            = azurerm_resource_group.aadds.location
  tags                = var.tags

  ip_configuration {
    name                          = "ipconfig1"
    private_ip_address_allocation = "dynamic"
    subnet_id                     = azurerm_subnet.aadds.id
  }

  depends_on = [
    azurerm_active_directory_domain_service.aadds
  ]
}

resource "azurerm_windows_virtual_machine" "aadds" {
  name                = local.vm_name
  resource_group_name = azurerm_resource_group.aadds.name
  location            = azurerm_resource_group.aadds.location
  size                = "Standard_B2ms"
  admin_username      = var.local_vm_username
  admin_password      = var.local_vm_password
  license_type        = "Windows_Server"
  tags                = var.tags

  network_interface_ids = [
    azurerm_network_interface.aadds.id
  ]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2019-Datacenter"
    version   = "latest"
  }

  identity {
    type = "SystemAssigned"
  }

  winrm_listener {
    protocol = "Http"
  }

  # provisioner "remote-exec" {
  #   inline = [
  #     "$url = \"https://raw.githubusercontent.com/ansible/ansible/devel/examples/scripts/ConfigureRemotingForAnsible.ps1\"",
  #     "$file = \"$env:temp\\ConfigureRemotingForAnsible.ps1\"",
  #     "(New-Object -TypeName System.Net.WebClient).DownloadFile($url, $file)",
  #     "powershell.exe -ExecutionPolicy ByPass -File $file"
  #   ]

  #   connection {
  #     type     = "winrm"
  #     user     = "azadmin"
  #     password = random_password.aadds.result
  #     host     = azurerm_public_ip.adds.ip_address
  #     agent    = "false"
  #     https    = "true"
  #     insecure = "true"
  #   }
  # }
}

######################################################################
# JOIN VM TO DOMAIN - YOU CAN'T DO THIS UNTIL YOU RESET YOUR PASSWORD
######################################################################

# https://docs.microsoft.com/en-us/azure/active-directory-domain-services/join-windows-vm-template
# Get-AzVMExtensionImage -Location westus2 -PublisherName "Microsoft.Compute" -Type “JsonADDomainExtension"
resource "azurerm_virtual_machine_extension" "aadds" {
  name                       = "JsonADDomainExtension"
  virtual_machine_id         = azurerm_windows_virtual_machine.aadds.id
  publisher                  = "Microsoft.Compute"
  type                       = "JsonADDomainExtension"
  type_handler_version       = "1.3"
  auto_upgrade_minor_version = true
  tags                       = var.tags

  settings = <<SETTINGS
    {
      "Name": "${var.aadds_domain_name}",
      "User": "${var.aadds_domain_join_username}",
      "Restart": "true",
      "Options": "3"
    }
  SETTINGS

  protected_settings = <<PROTECTED_SETTINGS
    {
      "Password": "${var.domain_admin_password}"
    }
  PROTECTED_SETTINGS

  depends_on = [
    azuread_group_member.aadds,
    azurerm_windows_virtual_machine.aadds
  ]
}

resource "azurerm_dev_test_global_vm_shutdown_schedule" "aadds" {
  virtual_machine_id = azurerm_windows_virtual_machine.aadds.id
  location           = azurerm_resource_group.aadds.location
  enabled            = true

  daily_recurrence_time = "1000"
  timezone              = "Pacific Standard Time"

  notification_settings {
    enabled         = true
    time_in_minutes = "15"
    email           = "pauyu@microsoft.com"
  }
}