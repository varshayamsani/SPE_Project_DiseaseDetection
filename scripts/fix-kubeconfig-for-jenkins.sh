#!/bin/bash

# Script to fix kubeconfig for Jenkins when running with minikube
# This updates the server URL to be accessible from Jenkins

set -e

KUBECONFIG_FILE="${1:-jenkins-kubeconfig.yaml}"
MINIKUBE_IP=$(minikube ip 2>/dev/null || echo "")

if [ -z "$MINIKUBE_IP" ]; then
    echo "ERROR: Could not get minikube IP. Is minikube running?"
    exit 1
fi

echo "=========================================="
echo "Fixing Kubeconfig for Jenkins"
echo "=========================================="
echo ""
echo "Minikube IP: $MINIKUBE_IP"
echo "Kubeconfig file: $KUBECONFIG_FILE"
echo ""

if [ ! -f "$KUBECONFIG_FILE" ]; then
    echo "ERROR: Kubeconfig file not found: $KUBECONFIG_FILE"
    echo ""
    echo "First, create a kubeconfig file:"
    echo "  ./scripts/create-jenkins-kubeconfig.sh $KUBECONFIG_FILE"
    exit 1
fi

# Get current server URL
CURRENT_SERVER=$(kubectl config view --kubeconfig="$KUBECONFIG_FILE" --minify -o jsonpath='{.clusters[0].cluster.server}' 2>/dev/null || echo "")

if [ -z "$CURRENT_SERVER" ]; then
    echo "ERROR: Could not read server URL from kubeconfig"
    exit 1
fi

echo "Current server URL: $CURRENT_SERVER"
echo ""

# Extract port from current server URL
if [[ $CURRENT_SERVER =~ :([0-9]+)$ ]]; then
    PORT="${BASH_REMATCH[1]}"
    echo "Detected port: $PORT"
else
    PORT="6443"
    echo "Using default port: $PORT"
fi

NEW_SERVER="https://$MINIKUBE_IP:$PORT"
echo "New server URL: $NEW_SERVER"
echo ""

# Test connectivity to new server
echo "Testing connectivity to $NEW_SERVER..."
if timeout 5 bash -c "echo > /dev/tcp/$MINIKUBE_IP/$PORT" 2>/dev/null; then
    echo "✅ Port $PORT is reachable on $MINIKUBE_IP"
else
    echo "⚠️  Port $PORT is not directly reachable"
    echo "   This might be normal - minikube uses port forwarding"
    echo "   We'll try using localhost with port forwarding instead"
    NEW_SERVER="https://127.0.0.1:$PORT"
fi
echo ""

# Backup original file
BACKUP_FILE="${KUBECONFIG_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
cp "$KUBECONFIG_FILE" "$BACKUP_FILE"
echo "✅ Backup created: $BACKUP_FILE"
echo ""

# Update server URL in kubeconfig
if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS
    sed -i '' "s|server:.*|server: $NEW_SERVER|g" "$KUBECONFIG_FILE"
else
    # Linux
    sed -i "s|server:.*|server: $NEW_SERVER|g" "$KUBECONFIG_FILE"
fi

echo "✅ Updated kubeconfig server URL to: $NEW_SERVER"
echo ""

# Verify the update
UPDATED_SERVER=$(kubectl config view --kubeconfig="$KUBECONFIG_FILE" --minify -o jsonpath='{.clusters[0].cluster.server}' 2>/dev/null || echo "")
echo "Verified server URL: $UPDATED_SERVER"
echo ""

# Test connectivity with updated kubeconfig
echo "Testing cluster connectivity with updated kubeconfig..."
if KUBECONFIG="$KUBECONFIG_FILE" kubectl cluster-info --request-timeout=10s &>/dev/null; then
    echo "✅ Cluster is accessible with updated kubeconfig!"
    echo ""
    KUBECONFIG="$KUBECONFIG_FILE" kubectl cluster-info
else
    echo "⚠️  Warning: Could not verify connectivity"
    echo "   The kubeconfig has been updated, but connectivity test failed"
    echo "   This might be normal if Jenkins runs in a different network context"
    echo ""
    echo "   Try these alternatives:"
    echo "   1. Use host.docker.internal if Jenkins is in Docker:"
    echo "      sed -i '' 's|server:.*|server: https://host.docker.internal:$PORT|g' $KUBECONFIG_FILE"
    echo ""
    echo "   2. Use the host machine's IP address"
    echo "   3. Ensure Jenkins can access the minikube network"
fi
echo ""

echo "=========================================="
echo "Next Steps"
echo "=========================================="
echo ""
echo "1. Update Jenkins credentials with the new kubeconfig:"
echo "   - Go to Jenkins → Manage Jenkins → Manage Credentials"
echo "   - Edit the 'kubeconfig' credential"
echo "   - Upload or paste the contents of: $KUBECONFIG_FILE"
echo ""
echo "2. Re-run your Jenkins pipeline"
echo ""
echo "3. If it still doesn't work, check:"
echo "   - Is Jenkins running in Docker? Use host.docker.internal"
echo "   - Is Jenkins on a different machine? Use the actual IP"
echo "   - Is minikube running? Run 'minikube status'"
echo ""




