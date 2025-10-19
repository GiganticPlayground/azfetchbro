output "key_vault_id" {
  value       = azurerm_key_vault.kv.id
}

output "key_vault_uri" {
  value       = azurerm_key_vault.kv.vault_uri
}

output "service_principal_client_id" {
  value       = azuread_service_principal.sp.client_id
  description = "Use as AZURE_CLIENT_ID"
}

output "service_principal_client_secret" {
  value       = azuread_service_principal_password.sp_pwd.value
  sensitive   = true
  description = "Use as AZURE_CLIENT_SECRET"
}

output "tenant_id" {
  value       = data.azurerm_client_config.current.tenant_id
  description = "Use as AZURE_TENANT_ID"
}

# Map of secrets created in Key Vault (name -> value)
# This mirrors the input var.secrets to make values available to automation scripts
# Marked sensitive to avoid accidental console display
output "created_secrets" {
  value       = var.secrets
  sensitive   = true
  description = "Key Vault secrets created by this stack as a map of name->value"
}