#!/bin/bash

# Common Azure helper functions to be sourced by x-plan.sh and x-apply.sh

check_az_cli() {
  if ! command -v az &> /dev/null; then
    echo "Error: Azure CLI is not installed. Please install it first."
    exit 1
  fi
  echo "Azure CLI is installed."
}

check_az_login() {
  if ! az account show &> /dev/null; then
    echo "Error: You are not logged into Azure. Please run 'az login' first."
    exit 1
  fi

  # Affirm login with current account info
  local account
  account="$(az account show --query user.name -o tsv 2>/dev/null || true)"
  if [[ -n "$account" ]]; then
    echo "Logged into Azure as: $account"
  else
    echo "Logged into Azure."
  fi

  # Expect subscription_id to be exported (e.g., via parsed tfvars)
  if [[ -n "$subscription_id" ]]; then
    current_sub=$(az account show --query id -o tsv)
    if [[ "$current_sub" != "$subscription_id" ]]; then
      echo "Error: Current subscription ($current_sub) does not match required subscription ($subscription_id)"
      echo "Please run: az account set --subscription $subscription_id"
      exit 1
    fi
    # Affirm subscription access
    local sub_name
    sub_name="$(az account show --query name -o tsv 2>/dev/null || true)"
    if [[ -n "$sub_name" ]]; then
      echo "Azure subscription confirmed: $sub_name ($current_sub)."
    else
      echo "Azure subscription confirmed: $current_sub."
    fi
  fi
}
