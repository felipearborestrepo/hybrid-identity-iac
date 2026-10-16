locals {
  config = yamldecode(file("${path.module}/identities.yaml"))

  # Turn the YAML lists into maps keyed by name, so Terraform
  # tracks each user and group individually.
  users  = { for u in local.config.users : u.username => u }
  groups = { for g in local.config.groups : g.name => g }

  domain = data.azuread_domains.initial.domains[0].domain_name
}

# The tenant's built-in domain, e.g. contoso.onmicrosoft.com
data "azuread_domains" "initial" {
  only_initial = true
}

# ---------------------------------------------------------------- users

# A random starting password per user. Users must change it at first sign-in.
resource "random_password" "initial" {
  for_each = local.users

  length           = 20
  special          = true
  override_special = "!@#%*-_"
  min_upper        = 2
  min_lower        = 2
  min_numeric      = 2
  min_special      = 2
}

resource "azuread_user" "lab" {
  for_each = local.users

  user_principal_name   = "${each.value.username}@${local.domain}"
  mail_nickname         = each.value.username
  display_name          = "${each.value.first_name} ${each.value.last_name}"
  given_name            = each.value.first_name
  surname               = each.value.last_name
  job_title             = each.value.job_title
  department            = each.value.department
  company_name          = local.config.company
  password              = random_password.initial[each.key].result
  force_password_change = true
}

# ---------------------------------------------------------------- groups

# One static security group per department.
resource "azuread_group" "department" {
  for_each = local.groups

  display_name     = each.value.name
  description      = each.value.description
  security_enabled = true
}

resource "azuread_group_member" "department" {
  for_each = local.users

  group_object_id  = azuread_group.department[each.value.group].object_id
  member_object_id = azuread_user.lab[each.key].object_id
}

# Dynamic group used to scope what is provisioned to Okta
# (the same rule as the manual lab). Requires Entra ID P1.
resource "azuread_group" "okta_synced_users" {
  display_name     = "Okta Synced Users"
  description      = "Users in scope for provisioning to Okta (managed by Terraform)"
  security_enabled = true
  types            = ["DynamicMembership"]

  dynamic_membership {
    enabled = true
    rule    = "(user.companyName -eq \"${local.config.company}\") and (user.accountEnabled -eq true)"
  }
}
