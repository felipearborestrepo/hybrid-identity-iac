output "resource_group" {
  value = azurerm_resource_group.lab.name
}

output "dc_vm_name" {
  value = azurerm_windows_virtual_machine.dc.name
}

output "dc_private_ip" {
  value = local.dc_ip
}

output "domain" {
  value = var.domain_name
}

output "admin_username" {
  value = "${var.netbios_name}\\${var.admin_username}"
}

output "bastion_enabled" {
  value = var.enable_bastion
}

# Hidden by default. Show with: terraform output -raw admin_password
output "admin_password" {
  value     = random_password.vm_admin.result
  sensitive = true
}

# Hidden by default. Show with: terraform output -raw ad_user_initial_password
output "ad_user_initial_password" {
  value     = random_password.ad_users.result
  sensitive = true
}
