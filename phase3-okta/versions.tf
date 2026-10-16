terraform {
  required_version = ">= 1.6"

  # State and runs live in HCP Terraform instead of on your Mac.
  cloud {
    organization = "felipe-iam-lab"

    workspaces {
      name = "hybrid-identity-okta"
    }
  }

  required_providers {
    okta = {
      source  = "okta/okta"
      version = ">= 4.0, < 5.0"
    }
  }
}

# Credentials come from environment variables set in the HCP Terraform
# workspace (OKTA_ORG_NAME, OKTA_BASE_URL, OKTA_API_TOKEN), never from files.
provider "okta" {}
