terraform {
  required_version = ">= 1.9"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "azurerm" {
  features {
    resource_group {
      # Allows destroying a resource group that still contains resources.
      # Set to true in production to prevent accidental destruction.
      prevent_deletion_if_contains_resources = false
    }
    virtual_machine {
      # Remove the OS disk when the VM is destroyed.
      delete_os_disk_on_deletion = true
      # Do not attempt a graceful OS shutdown on destroy — use force.
      graceful_shutdown              = false
      skip_shutdown_and_force_delete = false
    }
  }
  subscription_id = var.subscription_id
}
