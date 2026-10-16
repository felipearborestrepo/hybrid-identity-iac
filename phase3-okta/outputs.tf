output "groups" {
  description = "Okta groups created, with the rule that fills each one"
  value = {
    for k, g in okta_group.department : g.name => okta_group_rule.department[k].expression_value
  }
}

output "app" {
  value = {
    name           = okta_app_bookmark.reports.label
    assigned_group = okta_group.department[local.app_group].name
    policy         = okta_app_signon_policy.reports.name
  }
}

output "blocked_ip_ranges" {
  value = var.blocked_ip_ranges
}
