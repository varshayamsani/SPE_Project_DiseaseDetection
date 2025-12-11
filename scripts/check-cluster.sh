#!/bin/bash

# Kubernetes Cluster Diagnostic Script
# This script helps diagnose Kubernetes cluster connectivity issues

set -e

echo "=========================================="
echo "Kubernetes Cluster Diagnostic Script"
echo "=========================================="
echo ""

# Check if kubeconfig is provided
if [ -n "$1" ]; then
    export KUBECONFIG="$1"
    echo "Using kubeconfig: $1"
elif [ -n "$KUBECONFIG" ]; then
    echo "Using kubeconfig from KUBECONFIG env: $KUBECONFIG"
else
    echo "Using default kubeconfig location: ~/.kube/config"
    if [ -f ~/.kube/config ]; then
        export KUBECONFIG=~/.kube/config
    else
        echo "ERROR: No kubeconfig file found!"
        echo "Usage: $0 /path/to/kubeconfig"
        exit 1
    fi
fi

echo ""

# 1. Check if kubeconfig file exists
echo "1. Checking kubeconfig file..."
if [ -f "$KUBECONFIG" ]; then
    echo "   ✅ Kubeconfig file exists: $KUBECONFIG"
    echo "   File size: $(wc -c < "$KUBECONFIG") bytes"
else
    echo "   ❌ Kubeconfig file not found: $KUBECONFIG"
    exit 1
fi
echo ""

# 2. Check kubectl installation
echo "2. Checking kubectl installation..."
if command -v kubectl &> /dev/null; then
    echo "   ✅ kubectl is installed"
    kubectl version --client
else
    echo "   ❌ kubectl is not installed"
    exit 1
fi
echo ""

# 3. Check kubeconfig validity
echo "3. Validating kubeconfig syntax..."
if kubectl config view &>/dev/null; then
    echo "   ✅ Kubeconfig syntax is valid"
else
    echo "   ❌ Kubeconfig syntax is invalid"
    exit 1
fi
echo ""

# 4. Show current context
echo "4. Current context:"
CURRENT_CONTEXT=$(kubectl config current-context 2>&1)
if [ $? -eq 0 ]; then
    echo "   ✅ Current context: $CURRENT_CONTEXT"
else
    echo "   ❌ Could not get current context: $CURRENT_CONTEXT"
fi
echo ""

# 5. Show cluster server URL
echo "5. Cluster server URL:"
SERVER_URL=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}' 2>&1)
if [ $? -eq 0 ] && [ -n "$SERVER_URL" ]; then
    echo "   ✅ Server URL: $SERVER_URL"
    
    # Extract host and port for connectivity test
    if [[ $SERVER_URL =~ https?://([^:/]+)(:([0-9]+))? ]]; then
        HOST="${BASH_REMATCH[1]}"
        PORT="${BASH_REMATCH[3]:-443}"
        echo "   Host: $HOST"
        echo "   Port: $PORT"
        
        # Test basic connectivity
        echo "   Testing connectivity..."
        if timeout 5 bash -c "echo > /dev/tcp/$HOST/$PORT" 2>/dev/null; then
            echo "   ✅ Port $PORT is reachable on $HOST"
        else
            echo "   ⚠️  Port $PORT is not reachable on $HOST"
            echo "      This might be normal if the cluster uses a different protocol"
        fi
    fi
else
    echo "   ❌ Could not get server URL: $SERVER_URL"
fi
echo ""

# 6. Test cluster connectivity
echo "6. Testing cluster connectivity..."
echo "   (This may take up to 15 seconds...)"
CLUSTER_INFO=$(kubectl cluster-info --request-timeout=15s 2>&1)
CLUSTER_INFO_EXIT=$?

if [ $CLUSTER_INFO_EXIT -eq 0 ]; then
    echo "   ✅ Cluster is accessible"
    echo ""
    echo "$CLUSTER_INFO"
else
    echo "   ❌ Cannot connect to cluster"
    echo ""
    echo "Error output:"
    echo "$CLUSTER_INFO"
    echo ""
    echo "=========================================="
    echo "TROUBLESHOOTING SUGGESTIONS"
    echo "=========================================="
    echo ""
    
    if [[ "$SERVER_URL" == *"127.0.0.1"* ]] || [[ "$SERVER_URL" == *"localhost"* ]]; then
        echo "⚠️  Localhost detected in server URL: $SERVER_URL"
        echo ""
        echo "This appears to be a local cluster (minikube/Docker Desktop)."
        echo ""
        echo "Checking if minikube is running..."
        if command -v minikube &> /dev/null; then
            MINIKUBE_STATUS=$(minikube status 2>&1)
            if echo "$MINIKUBE_STATUS" | grep -q "host: Running"; then
                echo "   ✅ Minikube is running"
            else
                echo "   ❌ Minikube is NOT running"
                echo ""
                echo "   To start minikube, run:"
                echo "   minikube start"
                echo ""
            fi
        fi
        
        echo "If Jenkins runs on a different machine, localhost won't work."
        echo "Solutions:"
        echo "  1. Ensure Jenkins runs on the same machine as the cluster"
        echo "  2. Use the actual IP address or hostname instead of localhost"
        echo "  3. Set up port forwarding or a proxy"
        echo ""
    fi
    
    if [[ "$CLUSTER_INFO" == *"TLS handshake timeout"* ]]; then
        echo "⚠️  TLS handshake timeout detected"
        echo ""
        echo "Possible causes:"
        echo "  1. Cluster is not running"
        echo "  2. Network connectivity issues"
        echo "  3. Firewall blocking the connection"
        echo ""
        echo "Solutions:"
        echo "  - For minikube: run 'minikube status' and 'minikube start' if needed"
        echo "  - For Docker Desktop: enable Kubernetes in settings"
        echo "  - Check firewall rules"
        echo ""
    fi
    
    if [[ "$CLUSTER_INFO" == *"connection refused"* ]]; then
        echo "⚠️  Connection refused detected"
        echo ""
        echo "The cluster server is not accepting connections."
        echo "Verify the cluster is running and the server URL is correct."
        echo ""
    fi
    
    exit 1
fi
echo ""

# 7. Test node access
echo "7. Testing node access..."
if kubectl get nodes --request-timeout=10s &>/dev/null; then
    echo "   ✅ Successfully retrieved nodes"
    echo ""
    kubectl get nodes
else
    echo "   ⚠️  Could not retrieve nodes (but cluster-info succeeded)"
    echo "   This might indicate permission issues"
fi
echo ""

# 8. Test namespace access
echo "8. Testing namespace access..."
if kubectl get namespaces --request-timeout=10s &>/dev/null; then
    echo "   ✅ Successfully retrieved namespaces"
    echo ""
    kubectl get namespaces
else
    echo "   ⚠️  Could not retrieve namespaces"
fi
echo ""

echo "=========================================="
echo "Diagnostic Complete"
echo "=========================================="
echo ""
echo "If all checks passed, your cluster is ready for deployment!"

