terraform {
    required_version = ">= 1.5.0"

    required_providers {
        azurerm = {
            source  = "hashicorp/azurerm"
            version = "~> 4.0"
        }
        azuread = {
            source  = "hashicorp/azuread"
            version = "~> 2.47"
        }
        random = {
            source  = "hashicorp/random"
            version = "~> 3.6"
        }
    }
}

provider "azurerm" {
    features {}
    subscription_id = var.subscription_id
}

provider "azuread" {}