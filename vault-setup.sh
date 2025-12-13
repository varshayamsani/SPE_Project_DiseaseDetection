#!/bin/bash
# Vault Setup Script for Disease Detector
# This script configures Vault running in Kubernetes and stores application secrets
# 
# Usage:
#   For Kubernetes Vault (dev mode): ./vault-setup.sh
#   For local Vault: VAULT_ADDR=http://localhost:8200 ./vault-setup.sh

set -e

VAULT_ADDR=${VAULT_ADDR:-"http://vault.disease-detector.svc.cluster.local:8200"}
VAULT_TOKEN=${VAULT_TOKEN:-"root-token-12345"}  # Dev mode token

echo "=========================================="
echo "Setting up Vault for Disease Detector..."
echo "=========================================="
echo "Vault Address: $VAULT_ADDR"
echo ""

# Wait for Vault to be ready (if running in Kubernetes)
if [[ "$VAULT_ADDR" == *"vault.disease-detector"* ]]; then
    echo "Waiting for Vault service to be ready..."
    MAX_RETRIES=30
    RETRY_COUNT=0
    
    while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
        if curl -s -f "$VAULT_ADDR/v1/sys/health" > /dev/null 2>&1; then
            echo "✅ Vault is ready!"
            break
        fi
        RETRY_COUNT=$((RETRY_COUNT + 1))
        echo "  Attempt $RETRY_COUNT/$MAX_RETRIES - Waiting for Vault..."
        sleep 2
    done
    
    if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
        echo "❌ Vault is not accessible at $VAULT_ADDR"
        echo "   Make sure Vault is deployed: kubectl get pods -n disease-detector -l app=vault"
        exit 1
    fi
fi

# Set Vault token
export VAULT_ADDR
export VAULT_TOKEN

# Check if KV v2 secrets engine is already enabled
if vault secrets list | grep -q "disease-detector/"; then
    echo "ℹ️  KV secrets engine already enabled at disease-detector/"
else
    echo "Enabling KV v2 secrets engine..."
    vault secrets enable -path=disease-detector kv-v2 || {
        echo "⚠️  Failed to enable secrets engine (may already be enabled)"
    }
fi

echo ""
echo "Storing application secrets..."

# Store application configuration (used by backend pods)
echo "  - Storing application config..."
vault kv put disease-detector/app \
    flask_env="production" \
    log_level="INFO" \
    elasticsearch_host="elasticsearch.disease-detector.svc.cluster.local" \
    elasticsearch_port="9200" \
    database_path="/app/data/patients.db" \
    cors_origins="http://disease-detector-frontend.disease-detector.svc.cluster.local,http://localhost:3000"

# Store database configuration
echo "  - Storing database config..."
vault kv put disease-detector/database \
    path="/app/data/patients.db" \
    type="sqlite"

# Create policy for application pods (read-only access)
echo ""
echo "Creating Vault policy..."
vault policy write disease-detector-policy - <<EOF
# Allow reading application secrets
path "disease-detector/data/app" {
  capabilities = ["read"]
}

path "disease-detector/data/database" {
  capabilities = ["read"]
}

# Allow listing (for discovery)
path "disease-detector/metadata/*" {
  capabilities = ["list"]
}
EOF

# For dev mode, we use the root token
# In production, create a service account token
if [ "$VAULT_TOKEN" = "root-token-12345" ]; then
    echo ""
    echo "ℹ️  Using dev mode root token (root-token-12345)"
    echo "   In production, use Kubernetes service account authentication"
    APP_TOKEN="root-token-12345"
else
    echo ""
    echo "Creating application token..."
    APP_TOKEN=$(vault token create -policy=disease-detector-policy -format=json 2>/dev/null | jq -r '.auth.client_token' || echo "root-token-12345")
fi

# Save credentials
echo "VAULT_ADDR=$VAULT_ADDR" > vault-credentials.txt
echo "VAULT_TOKEN=$VAULT_TOKEN" >> vault-credentials.txt
echo "APP_TOKEN=$APP_TOKEN" >> vault-credentials.txt

echo ""
echo "=========================================="
echo "✅ Vault setup completed!"
echo "=========================================="
echo ""
echo "Stored secrets:"
echo "  - disease-detector/app (application config)"
echo "  - disease-detector/database (database config)"
echo ""
echo "Vault credentials saved to: vault-credentials.txt"
echo ""
echo "To verify secrets:"
echo "  vault kv get disease-detector/app"
echo "  vault kv get disease-detector/database"
echo ""
echo "To access Vault UI (if running locally):"
echo "  http://localhost:8200"
echo "  Token: $VAULT_TOKEN"
echo ""


