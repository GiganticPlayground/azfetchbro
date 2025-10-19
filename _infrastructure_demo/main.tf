data "azurerm_client_config" "current" {}

# Resource Group
resource "azurerm_resource_group" "rg" {
  name     = var.resource_group_name
  location = var.location
}

# Key Vault
resource "azurerm_key_vault" "kv" {
  name                          = var.key_vault_name
  location                      = azurerm_resource_group.rg.location
  resource_group_name           = azurerm_resource_group.rg.name
  tenant_id                     = data.azurerm_client_config.current.tenant_id
  sku_name                      = "standard"

  # Keep defaults sane; toggle to your policy standards as needed
  soft_delete_retention_days    = 7
  purge_protection_enabled      = true
  public_network_access_enabled = true

  # Use Azure RBAC for data-plane authorization (no access policies)
  rbac_authorization_enabled = true
}

# AAD App + Service Principal for Key Vault access
resource "azuread_application" "app" {
  display_name = "${var.key_vault_name}-sp-app"
}

resource "azuread_service_principal" "sp" {
  client_id = azuread_application.app.client_id
}

# Create a client secret for the SP (so you can auth)
resource "random_password" "sp_secret" {
  length           = 40
  min_lower        = 1
  min_upper        = 1
  min_numeric      = 1
  min_special      = 1
  override_special = "!@#$%^*()-_=+[]{}<>.?~"
}

resource "azuread_service_principal_password" "sp_pwd" {
  service_principal_id = azuread_service_principal.sp.id
  start_date           = timestamp()
  end_date             = timeadd(timestamp(), "8760h") # 1 year ahead
}

# Grant the SP rights to read secrets in the vault via RBAC
resource "azurerm_role_assignment" "sp_kv_access" {
  scope                = azurerm_key_vault.kv.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azuread_service_principal.sp.object_id
}

# Ensure the current signed-in user can create and manage secrets during apply
resource "azurerm_role_assignment" "current_user_kv_secrets_officer" {
  scope                = azurerm_key_vault.kv.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

# Create secrets (supports 1..N via var.secrets)
resource "azurerm_key_vault_secret" "secrets" {
  for_each     = nonsensitive(var.secrets)
  name         = each.key
  value        = each.value
  key_vault_id = azurerm_key_vault.kv.id

  # If you rotate via terraform changes, keep the latest activation timestamp
  content_type = "managed-by-terraform"

  # Ensure the current user's RBAC is in place before secret ops
  depends_on = [
    azurerm_role_assignment.current_user_kv_secrets_officer
  ]
}