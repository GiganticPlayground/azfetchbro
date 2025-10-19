#!/bin/bash

# Source common Azure helpers
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/x-common/common.sh"

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

# Validate Azure CLI presence and login/subscription before destroy
check_az_cli
check_az_login

# Confirm that the user wants to destroy the infrastructure
echo "This will DESTROY the infrastructure in Azure Subscription ID = ${subscription_id}."
read -p "Are you sure you want to proceed with destroy? (Ctrl+C to Stop, or any key to proceed) " -n 1 -r
printf "\nProceeding with destroy...\n"

# Before destroying, attempt to collect names of local secret files to remove
# We'll use Terraform outputs to determine the KV secret names
SECRET_FILES_TO_REMOVE=()
if command -v jq >/dev/null 2>&1; then
  TF_OUTPUT_JSON=$(terraform output -json 2>/dev/null || true)
  if [[ -n "$TF_OUTPUT_JSON" ]]; then
    if echo "$TF_OUTPUT_JSON" | jq -e '.created_secrets.value' >/dev/null 2>&1; then
      while IFS= read -r name; do
        SECRET_FILES_TO_REMOVE+=("./secrets/${name}")
      done < <(echo "$TF_OUTPUT_JSON" | jq -r '.created_secrets.value | keys[]')
    fi
    # Always include SP client secret file name
    SECRET_FILES_TO_REMOVE+=("./secrets/service_principal_client_secret")
  fi
fi

# Proceed with destroy (include secrets var-file if present)
if [[ -f "terraform.secrets.tfvars" ]]; then
  terraform destroy -var-file=terraform.secrets.tfvars
else
  terraform destroy
fi

# After destroy, remove local secret files (tolerate missing)
if [[ ${#SECRET_FILES_TO_REMOVE[@]} -gt 0 ]]; then
  for f in "${SECRET_FILES_TO_REMOVE[@]}"; do
    if [[ -e "$f" ]]; then
      rm -f "$f" && echo "Removed secret file: $f" || echo "Warning: failed to remove $f"
    fi
  done
  # If secrets directory is empty, remove it
  if [[ -d ./secrets ]] && [[ -z "$(ls -A ./secrets 2>/dev/null)" ]]; then
    rmdir ./secrets 2>/dev/null || true
  fi
fi
