#!/bin/bash
# Vault Setup Script for Disease Detector
# This script initializes Vault and stores application secrets

set -e

VAULT_ADDR=${VAULT_ADDR:-"http://localhost:8200"}
VAULT_TOKEN=${VAULT_TOKEN:-""}

echo "Setting up Vault for Disease Detector..."

# Initialize Vault (only if not already initialized)
if [ -z "$VAULT_TOKEN" ]; then
    echo "Initializing Vault..."
    vault operator init -key-shares=1 -key-threshold=1 > vault-init.txt
    
    # Extract unseal key and root token
    UNSEAL_KEY=$(grep 'Unseal Key' vault-init.txt | awk '{print $4}')
    ROOT_TOKEN=$(grep 'Initial Root Token' vault-init.txt | awk '{print $4}')
    
    echo "Unsealing Vault..."
    vault operator unseal $UNSEAL_KEY
    
    export VAULT_TOKEN=$ROOT_TOKEN
    echo "Root Token: $ROOT_TOKEN" > vault-credentials.txt
    echo "⚠️  IMPORTANT: Save vault-credentials.txt securely!"
fi

# Enable KV secrets engine
vault secrets enable -path=disease-detector kv-v2

# Store Docker Hub credentials
vault kv put disease-detector/docker \
    username="your-dockerhub-username" \
    password="your-dockerhub-password"

# Store database credentials
vault kv put disease-detector/database \
    path="/app/data/patients.db"

# Store application configuration
vault kv put disease-detector/app \
    flask_env="production" \
    log_level="INFO" \
    elasticsearch_host="elasticsearch" \
    elasticsearch_port="9200"

# Create policy for application
vault policy write disease-detector-policy - <<EOF
path "disease-detector/data/*" {
  capabilities = ["read"]
}
EOF

# Create token for application
APP_TOKEN=$(vault token create -policy=disease-detector-policy -format=json | jq -r '.auth.client_token')
echo "Application Token: $APP_TOKEN" >> vault-credentials.txt

echo "✅ Vault setup completed!"
echo "Application token saved to vault-credentials.txt"


