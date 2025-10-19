# azfetchbro Infrastructure Demonstration Deployment

This folder contains a minimal Terraform stack and helper scripts to provision demo Azure resources used by the azfetchbro tool.

## What gets created
- Resource Group
- Azure Key Vault
- Azure AD Application + Service Principal (with a client secret)
- RBAC assignments to allow the SP to read Key Vault secrets and the current user to manage them
- One or more Key Vault secrets (from a map)

## Prerequisites
- Terraform 1.5+ installed
- Azure CLI installed and logged in (`az login`)

Helpful docs:
- Azure CLI: https://learn.microsoft.com/cli/azure/install-azure-cli

## Quick start
1. Open a terminal in this directory: `_infrastructure_demo`.
2. Log in to Azure if you haven't already: `az login`.
3. Create a private secrets file for your subscription and any sensitive values:
   - Copy `terraform.secrets.tfvars.example` to `terraform.secrets.tfvars`.
   - Edit `terraform.secrets.tfvars` and set `subscription_id = "<your-azure-subscription-guid>"`.
   - Optionally move sensitive `secrets` into this file.
4. Review (and optionally edit) `terraform.tfvars` to set:
   - `resource_group_name`, `location`, `key_vault_name`
   - a `secrets` map for demo secrets (or keep in the secrets file)
5. Initialize Terraform: `terraform init`.
6. Plan using the helper (auto-detects `terraform.secrets.tfvars` if present): `./x-plan.sh`.
7. Apply the saved plan: `./x-apply.sh`.
8. When done, destroy the demo resources: `./x-destroy.sh`.

## Notes
- `terraform.secrets.tfvars` is ignored by git and safe to keep locally.
- The helpers ensure you are logged in to Azure and that the active Azure subscription matches the provided `subscription_id`.
- Providers used (see versions.tf): azurerm `~> 4.0`, azuread `~> 2.47`, random `~> 3.6`.

## Secrets handling and SP secret rotation
- Running `./x-apply.sh` will regenerate the Service Principal client secret every time it runs. The script always overwrites `./secrets/service_principal_client_secret` with the newly created value after a successful apply.
- After a successful apply, secrets are saved into the local `./secrets` directory:
  - One file per secret, named by the secret key.
  - The Service Principal client secret is always overwritten on each apply.
  - Key Vault secret files are written once and not overwritten if they already exist.
- The destroy helper `./x-destroy.sh` removes the saved secret files and cleans up the `./secrets` directory when empty.
