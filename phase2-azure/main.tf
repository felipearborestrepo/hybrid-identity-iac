locals {
  # Same source of truth as Phase 1.
  identities = yamldecode(file("${path.module}/../phase1-entra/identities.yaml"))

  ad_users = [for u in local.identities.users : {
    username   = u.username
    first_name = u.first_name
    last_name  = u.last_name
    job_title  = u.job_title
    department = u.department
    group      = u.group
    company    = local.identities.company
  }]

  dc_ip = "10.0.1.4"

  tags = {
    project    = "hybrid-identity-iac"
    managed_by = "terraform"
  }
}

# ---------------------------------------------------------------- passwords

resource "random_password" "vm_admin" {
  length           = 24
  special          = true
  override_special = "!#%*-_"
  min_upper        = 2
  min_lower        = 2
  min_numeric      = 2
  min_special      = 2
}

resource "random_password" "dsrm" {
  length           = 24
  special          = true
  override_special = "!#%*-_"
  min_upper        = 2
  min_lower        = 2
  min_numeric      = 2
  min_special      = 2
}

# One temporary password for the lab's AD users; they must change it at first logon.
resource "random_password" "ad_users" {
  length           = 20
  special          = true
  override_special = "!#%*-_"
  min_upper        = 2
  min_lower        = 2
  min_numeric      = 2
  min_special      = 2
}

# ---------------------------------------------------------------- network

resource "azurerm_resource_group" "lab" {
  name     = "rg-${var.prefix}"
  location = var.location
  tags     = local.tags
}

resource "azurerm_virtual_network" "lab" {
  name                = "vnet-${var.prefix}"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  address_space       = ["10.0.0.0/16"]

  # Machines in the VNet use the DC for DNS (required for AD), with Azure DNS as fallback.
  dns_servers = [local.dc_ip, "168.63.129.16"]
  tags        = local.tags
}

resource "azurerm_subnet" "identity" {
  name                 = "snet-identity"
  resource_group_name  = azurerm_resource_group.lab.name
  virtual_network_name = azurerm_virtual_network.lab.name
  address_prefixes     = ["10.0.1.0/24"]
}

# Firewall rules for the identity subnet. There is no public IP on the DC, and
# the default rules already block inbound traffic from the internet. This rule
# makes it explicit that RDP is only allowed from inside the VNet (Bastion).
resource "azurerm_network_security_group" "identity" {
  name                = "nsg-${var.prefix}-identity"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  tags                = local.tags

  security_rule {
    name                       = "Allow-RDP-From-VNet"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3389"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "Deny-RDP-From-Internet"
    priority                   = 200
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3389"
    source_address_prefix      = "Internet"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "identity" {
  subnet_id                 = azurerm_subnet.identity.id
  network_security_group_id = azurerm_network_security_group.identity.id
}

# ---------------------------------------------------------------- domain controller

resource "azurerm_network_interface" "dc" {
  name                = "nic-${var.prefix}-dc01"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  tags                = local.tags

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.identity.id
    private_ip_address_allocation = "Static" # a DC's IP must never change
    private_ip_address            = local.dc_ip
  }
}

resource "azurerm_windows_virtual_machine" "dc" {
  name                  = "vm-${var.prefix}-dc01"
  computer_name         = "DC01"
  location              = azurerm_resource_group.lab.location
  resource_group_name   = azurerm_resource_group.lab.name
  size                  = var.vm_size
  admin_username        = var.admin_username
  admin_password        = random_password.vm_admin.result
  network_interface_ids = [azurerm_network_interface.dc.id]
  tags                  = local.tags

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
  }

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2022-datacenter-g2"
    version   = "latest"
  }
}

# Shut the VM down every evening so it doesn't run (and cost money) overnight.
resource "azurerm_dev_test_global_vm_shutdown_schedule" "dc" {
  virtual_machine_id    = azurerm_windows_virtual_machine.dc.id
  location              = azurerm_resource_group.lab.location
  enabled               = true
  daily_recurrence_time = var.shutdown_time
  timezone              = "Eastern Standard Time"

  notification_settings {
    enabled = false
  }
}

# Step 1 inside the VM: install AD DS, create the forest, then restart.
resource "azurerm_virtual_machine_run_command" "promote_dc" {
  name               = "promote-dc"
  location           = azurerm_resource_group.lab.location
  virtual_machine_id = azurerm_windows_virtual_machine.dc.id

  source {
    script = file("${path.module}/scripts/promote_dc.ps1")
  }

  parameter {
    name  = "DomainName"
    value = var.domain_name
  }

  parameter {
    name  = "NetbiosName"
    value = var.netbios_name
  }

  protected_parameter {
    name  = "SafeModePasswordB64"
    value = base64encode(random_password.dsrm.result)
  }

  timeouts {
    create = "60m"
  }
}

# Give the VM time to restart as a domain controller.
resource "time_sleep" "after_promotion" {
  depends_on      = [azurerm_virtual_machine_run_command.promote_dc]
  create_duration = "6m"
}

# Step 2 inside the VM: create the OU, groups and users from identities.yaml.
# Re-runs automatically whenever the YAML changes (joiners, movers, leavers).
resource "azurerm_virtual_machine_run_command" "ad_identities" {
  name               = "ad-identities"
  location           = azurerm_resource_group.lab.location
  virtual_machine_id = azurerm_windows_virtual_machine.dc.id
  depends_on         = [time_sleep.after_promotion]

  source {
    script = file("${path.module}/scripts/ad_identities.ps1")
  }

  parameter {
    name  = "UsersB64"
    value = base64encode(jsonencode(local.ad_users))
  }

  parameter {
    name  = "UpnSuffix"
    value = var.upn_suffix
  }

  parameter {
    name  = "OuName"
    value = var.ou_name
  }

  protected_parameter {
    name  = "PasswordB64"
    value = base64encode(random_password.ad_users.result)
  }

  timeouts {
    create = "60m"
    update = "60m"
  }
}

# ---------------------------------------------------------------- bastion (optional)

resource "azurerm_subnet" "bastion" {
  count                = var.enable_bastion ? 1 : 0
  name                 = "AzureBastionSubnet" # Azure requires this exact name
  resource_group_name  = azurerm_resource_group.lab.name
  virtual_network_name = azurerm_virtual_network.lab.name
  address_prefixes     = ["10.0.254.0/26"]
}

resource "azurerm_public_ip" "bastion" {
  count               = var.enable_bastion ? 1 : 0
  name                = "pip-${var.prefix}-bastion"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = local.tags
}

resource "azurerm_bastion_host" "lab" {
  count               = var.enable_bastion ? 1 : 0
  name                = "bas-${var.prefix}"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  sku                 = "Basic"
  tags                = local.tags

  ip_configuration {
    name                 = "configuration"
    subnet_id            = azurerm_subnet.bastion[0].id
    public_ip_address_id = azurerm_public_ip.bastion[0].id
  }
}
