output "tenant_domain" {
  value = local.domain
}

output "users" {
  description = "User principal names created by Terraform"
  value       = { for k, u in azuread_user.lab : k => u.user_principal_name }
}

output "groups" {
  description = "Group names and object IDs"
  value = merge(
    { for k, g in azuread_group.department : k => g.object_id },
    { "Okta Synced Users" = azuread_group.okta_synced_users.object_id }
  )
}

# Hidden by default. Show with: terraform output -json initial_passwords
output "initial_passwords" {
  value     = { for k, p in random_password.initial : k => p.result }
  sensitive = true
}
