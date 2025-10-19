#!/bin/bash

# Source common Azure helpers
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/x-common/common.sh"

# Check if tfplan file exists
if [ ! -f "tfplan" ]; then
    echo "Error: tfplan file not found. Please run x-plan.sh first."
    exit 1
fi

parse_tfvars() {
  local file="$1"
  [[ ! -f "$file" ]] && return 0
  while IFS= read -r line || [[ -n "$line" ]]; do
    # Remove inline comments and trim leading/trailing whitespace
    line="${line%%#*}"
    line="$(echo -e "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    # Skip empty lines and block markers
    [[ -z "$line" ]] && continue
    [[ "$line" == *"{"* || "$line" == *"}"* ]] && continue

    # Split into name and value
    varname="${line%%=*}"
    value="${line#*=}"

    # Normalize whitespace
    varname="$(echo -e "$varname" | sed -e 's/[[:space:]]//g')"
    value="$(echo -e "$value" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"

    # Strip surrounding quotes from value if present
    if [[ $value =~ ^\"(.*)\"$ ]]; then
      value="${BASH_REMATCH[1]}"
    fi

    # Only export valid identifiers
    if [[ $varname =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]; then
      export "$varname"="$value"
    fi
  done < "$file"
}

# Parse default tfvars and optional secrets tfvars for display context
parse_tfvars "terraform.tfvars"
parse_tfvars "terraform.secrets.tfvars"

# Validate Azure CLI presence and login/subscription before apply
check_az_cli
check_az_login

# Confirm that the user wants to apply the plan
echo "This will apply the plan to the infrastructure against Azure Sub ID = ${subscription_id}."
read -p "Are you sure you want to apply the plan? (Ctrl+C to Stop, or any key to proceed) " -n 1 -r
printf "\nProceeding with apply...\n"
terraform apply tfplan

# After successful apply, persist secrets to ./secrets without redaction
# Requirements:
# - 1 file per secret using the secret name
# - include the service principal client secret
# - do not overwrite existing files
# - show full secret value

# Ensure jq is available for parsing Terraform JSON outputs
if ! command -v jq >/dev/null 2>&1; then
  echo "Warning: 'jq' is not installed; cannot persist secrets to files automatically."
  echo "Install jq and re-run if you want files in ./secrets. Skipping secret file creation."
  exit 0
fi

# Fetch outputs as JSON
TF_OUTPUT_JSON=$(terraform output -json 2>/dev/null || true)
if [[ -z "$TF_OUTPUT_JSON" ]]; then
  echo "Warning: No Terraform outputs found; skipping secret file creation."
  exit 0
fi

mkdir -p ./secrets

write_secret_file() {
  local name="$1"
  local value="$2"
  local overwrite="${3:-false}"
  local path="./secrets/${name}"
  if [[ -e "$path" && "$overwrite" != "true" ]]; then
    echo "Secret file exists, not overwriting: $path"
    return 0
  fi
  # Write exact content without adding a trailing newline
  printf "%s" "$value" > "$path"
  chmod 600 "$path" 2>/dev/null || true
  if [[ "$overwrite" == "true" ]]; then
    echo "Wrote secret to $path (overwritten)"
  else
    echo "Wrote secret to $path"
  fi
}

# 1) Service Principal client secret
sp_secret=$(echo "$TF_OUTPUT_JSON" | jq -r '.service_principal_client_secret.value // empty')
if [[ -n "$sp_secret" ]]; then
  # Always overwrite SP client secret file on apply: Terraform re-creates it on each run
  write_secret_file "service_principal_client_secret" "$sp_secret" true
fi

# 2) Key Vault secrets created by this stack (map of name->value)
# created_secrets output is marked sensitive, but -json returns full values
# Iterate keys and write each to a file named by the secret key
if echo "$TF_OUTPUT_JSON" | jq -e '.created_secrets.value' >/dev/null 2>&1; then
  # Use POSIX-compatible while-read loop for macOS bash 3.2 (no mapfile)
  while IFS= read -r sname; do
    svalue=$(echo "$TF_OUTPUT_JSON" | jq -r --arg k "$sname" '.created_secrets.value[$k]')
    write_secret_file "$sname" "$svalue"
  done < <(echo "$TF_OUTPUT_JSON" | jq -r '.created_secrets.value | keys[]')
fi
