variable "subscription_id" {
  description = "Azure subscription ID to deploy into (az account show --query id -o tsv)"
  type        = string
}

variable "upn_suffix" {
  description = "Routable UPN suffix added to AD so users match Entra, e.g. contoso.onmicrosoft.com"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
  default     = "eastus2"
}

variable "prefix" {
  description = "Short prefix for resource names"
  type        = string
  default     = "hybiac"
}

variable "domain_name" {
  description = "AD forest (DNS) name"
  type        = string
  default     = "oktaentra.local"
}

variable "netbios_name" {
  description = "AD NetBIOS name"
  type        = string
  default     = "OKTAENTRA"
}

variable "ou_name" {
  description = "OU that holds the lab users (the OU you scope Entra Connect to)"
  type        = string
  default     = "EmployeesOktaIntegration"
}

variable "vm_size" {
  description = "Domain controller VM size"
  type        = string
  default     = "Standard_B2s"
}

variable "admin_username" {
  description = "Local administrator for the VM (becomes a domain admin after promotion)"
  type        = string
  default     = "labadmin"
}

variable "enable_bastion" {
  description = "Create Azure Bastion for RDP access. Costs money per hour, so only turn on when needed."
  type        = bool
  default     = false
}

variable "shutdown_time" {
  description = "Daily auto-shutdown time (24h, HHMM) in Eastern time, to save money"
  type        = string
  default     = "1900"
}
