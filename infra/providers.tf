terraform {
  required_version = ">= 1.9.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
  backend "azurerm" {} # settings come from backend.hcl
}

provider "azurerm" {
  features {}
  # Providers were registered by bootstrap.sh; the pipeline can't register them.
  resource_provider_registrations = "none"
  # Subscription comes from ARM_SUBSCRIPTION_ID. In GitHub Actions, ARM_USE_OIDC=true switches sign-in to OIDC.
}
