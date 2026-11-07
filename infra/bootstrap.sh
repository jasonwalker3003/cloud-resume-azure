#!/usr/bin/env bash
# One-off setup Terraform can't do for itself. Safe to re-run.
set -euo pipefail
: "${P1_PREFIX:?Run: source ~/p1.env}"

# Register the Azure services this project uses (the pipeline won't have permission to).
for ns in Microsoft.Web Microsoft.DocumentDB Microsoft.Insights \
          Microsoft.OperationalInsights Microsoft.Storage Microsoft.AlertsManagement; do
  az provider register --namespace "$ns" --output none
done

# Two resource groups: one for Terraform state, one for the app.
for rg in "$P1_TFSTATE_RG" "$P1_RG"; do
  az group create -n "$rg" -l "$P1_LOCATION" \
    --tags project=cloud-resume owner=jason env=prod -o none
done

# Storage for Terraform state, with versioning so a bad state file can be rolled back.
az storage account create -n "$P1_TFSTATE_SA" -g "$P1_TFSTATE_RG" -l "$P1_LOCATION" \
  --sku Standard_LRS --kind StorageV2 --min-tls-version TLS1_2 \
  --allow-blob-public-access false -o none
az storage account blob-service-properties update -n "$P1_TFSTATE_SA" -g "$P1_TFSTATE_RG" \
  --enable-versioning true --enable-delete-retention true --delete-retention-days 14 -o none
az storage container create -n tfstate --account-name "$P1_TFSTATE_SA" --auth-mode key -o none

echo "Bootstrap complete."