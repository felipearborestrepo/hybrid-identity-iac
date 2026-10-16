variable "group_prefix" {
  description = "Prefix for Terraform-managed Okta groups, so they don't clash with groups created by hand"
  type        = string
  default     = "TF-"
}

variable "app_department" {
  description = "Only this department gets the Reports Portal app (least privilege)"
  type        = string
  default     = "Engineering"
}

variable "blocked_ip_ranges" {
  description = "IP ranges denied access to the app. The default is a documentation-only range that blocks nobody."
  type        = list(string)
  default     = ["203.0.113.0/24"]
}
