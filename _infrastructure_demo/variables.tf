variable "subscription_id" {
  description = "Azure subscription ID"
  type        = string
}

variable "resource_group_name" {
  description = "Existing resource group to host the Key Vault"
  type        = string
}

variable "location" {
  description = "Azure region for the Key Vault"
  type        = string
}

variable "key_vault_name" {
  description = "Name of the Key Vault to create"
  type        = string
}

# Supply many secrets at once
# Example:
# secrets = {
#     apiKey       = "super-secret"
#     connection   = "Server=tcp:...;"
# }
variable "secrets" {
  description = "Map of secret_name => secret_value to create in the Key Vault"
  type        = map(string)
  default     = {}
  sensitive   = true
}