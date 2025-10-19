#!/bin/bash -e

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

# Parse default tfvars and optional secrets tfvars
parse_tfvars "terraform.tfvars"
parse_tfvars "terraform.secrets.tfvars"

check_az_cli
check_az_login

echo "This will plan against your Azure Sub ID = ${subscription_id}."
echo "If you need to login, use: az login"
read -p "Are you sure you want to continue? (Ctrl+C to Stop, or any key to proceed) " -n 1 -r
printf "\nProceeding with plan...\n"

# If secrets file exists, include it as a -var-file so Terraform gets subscription_id
if [[ -f "terraform.secrets.tfvars" ]]; then
  terraform plan -var-file=terraform.secrets.tfvars -out=tfplan
else
  terraform plan -out=tfplan
fi
