resource "random_id" "prefix" {
  byte_length = 8
}

resource "azurerm_resource_group" "main" {
  count = var.create_resource_group ? 1 : 0

  location = var.location
  name     = coalesce(var.resource_group_name, "${random_id.prefix.hex}-rg")
}

locals {
  resource_group = {
    name     = var.create_resource_group ? azurerm_resource_group.main[0].name : var.resource_group_name
    location = var.location
  }
}

resource "azurerm_virtual_network" "test" {
  address_space       = ["10.52.0.0/16"]
  location            = local.resource_group.location
  name                = "${random_id.prefix.hex}-vn"
  resource_group_name = local.resource_group.name
}

resource "azurerm_subnet" "test" {
  address_prefixes                               = ["10.52.0.0/24"]
  name                                           = "${random_id.prefix.hex}-sn"
  resource_group_name                            = local.resource_group.name
  virtual_network_name                           = azurerm_virtual_network.test.name
  enforce_private_link_endpoint_network_policies = true
}

resource "azurerm_dns_zone" "aks_web_app_routing" {
  name                = "fakeaks.com"
  resource_group_name = local.resource_group.name
}

module "aks_without_monitor" {
  source = "../.."

  prefix                        = "ops100-${random_id.prefix.hex}"
  resource_group_name           = local.resource_group.name
  admin_username                = null
  azure_policy_enabled          = true
  disk_encryption_set_id        = azurerm_disk_encryption_set.des.id
  public_network_access_enabled = false
  #checkov:skip=CKV_AZURE_4:The logging is turn off for demo purpose. DO NOT DO THIS IN PRODUCTION ENVIRONMENT!
  log_analytics_workspace_enabled   = false
  net_profile_pod_cidr              = "10.1.0.0/16"
  private_cluster_enabled           = true
  rbac_aad                          = true
  rbac_aad_managed                  = true
  role_based_access_control_enabled = true
  web_app_routing = {
    dns_zone_id = azurerm_dns_zone.aks_web_app_routing.id
  }
}

resource "azurerm_public_ip" "example" {
  name                = "${random_id.prefix.hex}-pip"
  location            = local.resource_group.location
  resource_group_name = local.resource_group.name
  allocation_method   = "Dynamic"
}

resource "azurerm_network_interface" "example" {
  name                = "${random_id.prefix.hex}-nic"
  location            = local.resource_group.location
  resource_group_name = local.resource_group.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.test.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.example.id
  }
}

resource "azurerm_linux_virtual_machine" "example" {
  name                = "${random_id.prefix.hex}-vm"
  resource_group_name = local.resource_group.name
  location            = local.resource_group.location
  size                = "Standard_B1s"
#  size                = "Standard_F2"
  admin_username      = "adminuser"
  network_interface_ids = [azurerm_network_interface.example.id]

  admin_ssh_key {
    username   = "adminuser"
    public_key = file("~/.ssh/id_rsa.pub")
  }
/*
  source_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "16.04-LTS"
    version   = "latest"
  }
*/
 source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  os_disk {
    name    = "app-os"
    caching = "ReadWrite" # TODO is this advisable?
    #disk_size_gb         = 30                # this is optional.
    storage_account_type = "StandardSSD_LRS" # Locally Redundant Storage.
  }

/*
  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }
*/
}
