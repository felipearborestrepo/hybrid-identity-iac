locals {
  # Same source of truth as Phases 1 and 2.
  identities = yamldecode(file("${path.module}/../phase1-entra/identities.yaml"))

  # Which department each group represents, taken from the users in the YAML.
  department_by_group = { for u in local.identities.users : u.group => u.department... }

  groups = {
    for g in local.identities.groups : g.name => {
      name        = "${var.group_prefix}${g.name}"
      description = "${g.description} (managed by Terraform)"
      department  = local.department_by_group[g.name][0]
    } if contains(keys(local.department_by_group), g.name)
  }

  app_group = one([for k, g in local.groups : k if g.department == var.app_department])
}

# ---------------------------------------------------------------- groups + rules

resource "okta_group" "department" {
  for_each = local.groups

  name        = each.value.name
  description = each.value.description
}

# Attribute-based membership: anyone whose Okta profile has this department
# is placed in the group automatically, and removed if the department changes.
resource "okta_group_rule" "department" {
  for_each = local.groups

  name              = substr("${each.value.name}-rule", 0, 50)
  status            = "ACTIVE"
  group_assignments = [okta_group.department[each.key].id]
  expression_type   = "urn:okta:expression:1.0"
  expression_value  = "user.department==\"${each.value.department}\""
}

# ---------------------------------------------------------------- zero trust policy

resource "okta_network_zone" "blocked" {
  name     = "TF-Blocked-Networks"
  type     = "IP"
  usage    = "POLICY"
  status   = "ACTIVE"
  gateways = var.blocked_ip_ranges
}

resource "okta_app_signon_policy" "reports" {
  name        = "TF-Reports-Portal-Policy"
  description = "Deny blocked networks; require MFA for the assigned department (managed by Terraform)"
}

# Rule 1: deny anyone coming from a blocked network, no matter who they are.
resource "okta_app_signon_policy_rule" "deny_blocked_networks" {
  policy_id          = okta_app_signon_policy.reports.id
  name               = "Deny blocked networks"
  priority           = 1
  access             = "DENY"
  network_connection = "ZONE"
  network_includes   = [okta_network_zone.blocked.id]
}

# Rule 2: allow the assigned department, but only with MFA, re-checked every 2 hours.
resource "okta_app_signon_policy_rule" "allow_department_mfa" {
  policy_id                   = okta_app_signon_policy.reports.id
  name                        = "Allow ${var.app_department} with MFA"
  priority                    = 2
  access                      = "ALLOW"
  factor_mode                 = "2FA"
  groups_included             = [okta_group.department[local.app_group].id]
  re_authentication_frequency = "PT2H"

  depends_on = [okta_app_signon_policy_rule.deny_blocked_networks]
}

# ---------------------------------------------------------------- app

resource "okta_app_bookmark" "reports" {
  label                 = "TF Reports Portal"
  url                   = "https://example.com"
  authentication_policy = okta_app_signon_policy.reports.id
}

# Least privilege: only the one department's group is assigned the app.
resource "okta_app_group_assignment" "reports" {
  app_id   = okta_app_bookmark.reports.id
  group_id = okta_group.department[local.app_group].id
}
