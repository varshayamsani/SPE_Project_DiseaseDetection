#!/bin/sh
# Startup script to load secrets from Vault
# This script reads secrets from /vault-secrets/ files and exports them as environment variables

if [ -d "/vault-secrets" ]; then
    echo "Loading secrets from Vault..."
    
    # Read each secret file and export as environment variable
    if [ -f "/vault-secrets/FLASK_ENV" ]; then
        export FLASK_ENV=$(cat /vault-secrets/FLASK_ENV)
        echo "  FLASK_ENV=$FLASK_ENV (from Vault)"
    fi
    
    if [ -f "/vault-secrets/LOG_LEVEL" ]; then
        export LOG_LEVEL=$(cat /vault-secrets/LOG_LEVEL)
        echo "  LOG_LEVEL=$LOG_LEVEL (from Vault)"
    fi
    
    if [ -f "/vault-secrets/ELASTICSEARCH_HOST" ]; then
        export ELASTICSEARCH_HOST=$(cat /vault-secrets/ELASTICSEARCH_HOST)
        echo "  ELASTICSEARCH_HOST=$ELASTICSEARCH_HOST (from Vault)"
    fi
    
    if [ -f "/vault-secrets/ELASTICSEARCH_PORT" ]; then
        export ELASTICSEARCH_PORT=$(cat /vault-secrets/ELASTICSEARCH_PORT)
        echo "  ELASTICSEARCH_PORT=$ELASTICSEARCH_PORT (from Vault)"
    fi
    
    if [ -f "/vault-secrets/DATABASE_PATH" ]; then
        export DATABASE_PATH=$(cat /vault-secrets/DATABASE_PATH)
        echo "  DATABASE_PATH=$DATABASE_PATH (from Vault)"
    fi
    
    if [ -f "/vault-secrets/CORS_ORIGINS" ]; then
        export CORS_ORIGINS=$(cat /vault-secrets/CORS_ORIGINS)
        echo "  CORS_ORIGINS=$CORS_ORIGINS (from Vault)"
    fi
    
    echo "✅ Secrets loaded from Vault"
else
    echo "⚠️  /vault-secrets directory not found, using default environment variables"
fi

# Execute the main command
exec "$@"

