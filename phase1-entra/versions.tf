terraform {
  required_version = ">= 1.6"

  required_providers {
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 3.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

# Locally, Terraform uses your "az login" session.
# In the pipeline (Phase 4) it will use a service principal instead.
provider "azuread" {}
