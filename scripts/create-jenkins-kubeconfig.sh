#!/bin/bash

# Script to create a kubeconfig file for Jenkins service account
# Usage: ./scripts/create-jenkins-kubeconfig.sh [output-file]

set -e

NAMESPACE="disease-detector"
SERVICE_ACCOUNT="jenkins-service-account"
OUTPUT_FILE="${1:-jenkins-kubeconfig.yaml}"

echo "=========================================="
echo "Creating Jenkins Kubeconfig"
echo "=========================================="
echo ""

# Check if service account exists
if ! kubectl get serviceaccount "$SERVICE_ACCOUNT" -n "$NAMESPACE" &>/dev/null; then
    echo "ERROR: Service account '$SERVICE_ACCOUNT' not found in namespace '$NAMESPACE'"
    echo "Creating service account and RBAC..."
    kubectl apply -f k8s/jenkins-service.yaml
    echo "Waiting for secret to be created..."
    sleep 5
fi

# Get cluster information
echo "1. Getting cluster information..."
# Get the actual server URL from cluster-info (most reliable)
CLUSTER_URL=$(kubectl cluster-info 2>/dev/null | grep "Kubernetes control plane" | awk '{print $NF}' | sed 's|https://||' | sed 's|http://||')
if [ -z "$CLUSTER_URL" ]; then
    # Fallback to config view if cluster-info fails
    CLUSTER_URL=$(kubectl config view --raw -o jsonpath='{.clusters[0].cluster.server}' | sed 's|https://||' | sed 's|http://||')
fi
# Ensure it has https:// prefix
if [[ ! "$CLUSTER_URL" =~ ^https?:// ]]; then
    CLUSTER_URL="https://$CLUSTER_URL"
fi
CLUSTER_NAME=$(kubectl config view --raw -o jsonpath='{.clusters[0].name}')
CONTEXT_NAME=$(kubectl config current-context)

echo "   Cluster URL: $CLUSTER_URL"
echo "   Cluster Name: $CLUSTER_NAME"
echo "   Context Name: $CONTEXT_NAME"
echo ""

# Get CA certificate
echo "2. Getting cluster CA certificate..."
# First try to get from minify (current context)
CA_DATA=$(kubectl config view --minify --raw -o jsonpath='{.clusters[0].cluster.certificate-authority-data}' 2>/dev/null)
if [ -z "$CA_DATA" ] || [ "$CA_DATA" == "null" ]; then
    # Try to get from file path (more reliable for minikube)
    CA_FILE=$(kubectl config view --minify --raw -o jsonpath='{.clusters[0].cluster.certificate-authority}' 2>/dev/null)
    if [ -n "$CA_FILE" ] && [ -f "$CA_FILE" ]; then
        if [[ "$OSTYPE" == "darwin"* ]]; then
            CA_DATA=$(base64 -i "$CA_FILE" | tr -d '\n')
        else
            CA_DATA=$(base64 -w 0 "$CA_FILE")
        fi
        echo "   ✅ CA certificate read from file: $CA_FILE"
    else
        # Try minikube default location
        MINIKUBE_CA="/Users/$USER/.minikube/ca.crt"
        if [ -f "$MINIKUBE_CA" ]; then
            if [[ "$OSTYPE" == "darwin"* ]]; then
                CA_DATA=$(base64 -i "$MINIKUBE_CA" | tr -d '\n')
            else
                CA_DATA=$(base64 -w 0 "$MINIKUBE_CA")
            fi
            echo "   ✅ CA certificate read from minikube default location"
        else
            echo "   ⚠️  Warning: Could not get CA certificate, using insecure connection"
            CA_DATA=""
        fi
    fi
else
    echo "   ✅ CA certificate retrieved from config"
fi
echo ""

# Create token with longer timeout
echo "3. Creating service account token..."
echo "   (This may take up to 30 seconds...)"
TOKEN=$(kubectl create token "$SERVICE_ACCOUNT" -n "$NAMESPACE" --duration=8760h --request-timeout=30s 2>&1)
if [ $? -ne 0 ]; then
    echo "   ❌ Failed to create token"
    echo "   Error: $TOKEN"
    echo ""
    echo "   Trying alternative method: using existing secret..."
    SECRET_NAME=$(kubectl get serviceaccount "$SERVICE_ACCOUNT" -n "$NAMESPACE" -o jsonpath='{.secrets[0].name}' 2>/dev/null || echo "")
    if [ -n "$SECRET_NAME" ]; then
        TOKEN=$(kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" -o jsonpath='{.data.token}' | base64 -d)
        echo "   ✅ Token retrieved from secret: $SECRET_NAME"
    else
        echo "   ❌ Could not retrieve token"
        exit 1
    fi
else
    echo "   ✅ Token created successfully"
fi
echo ""

# Create kubeconfig
echo "4. Creating kubeconfig file: $OUTPUT_FILE"
cat > "$OUTPUT_FILE" <<EOF
apiVersion: v1
kind: Config
clusters:
- cluster:
    server: $CLUSTER_URL
EOF

if [ -n "$CA_DATA" ]; then
    cat >> "$OUTPUT_FILE" <<EOF
    certificate-authority-data: $CA_DATA
EOF
else
    cat >> "$OUTPUT_FILE" <<EOF
    insecure-skip-tls-verify: true
EOF
fi

cat >> "$OUTPUT_FILE" <<EOF
  name: $CLUSTER_NAME
contexts:
- context:
    cluster: $CLUSTER_NAME
    namespace: $NAMESPACE
    user: $SERVICE_ACCOUNT
  name: jenkins-context
current-context: jenkins-context
users:
- name: $SERVICE_ACCOUNT
  user:
    token: $TOKEN
EOF

echo "   ✅ Kubeconfig file created"
echo ""

# Verify the kubeconfig
echo "5. Verifying kubeconfig..."
if KUBECONFIG="$OUTPUT_FILE" kubectl cluster-info --request-timeout=10s &>/dev/null; then
    echo "   ✅ Kubeconfig is valid and cluster is accessible"
    echo ""
    echo "   Testing with the new kubeconfig:"
    KUBECONFIG="$OUTPUT_FILE" kubectl get namespaces
else
    echo "   ⚠️  Warning: Could not verify kubeconfig (cluster might be unreachable)"
fi
echo ""

echo "=========================================="
echo "Kubeconfig Created Successfully!"
echo "=========================================="
echo ""
echo "File: $OUTPUT_FILE"
echo ""
echo "To use this kubeconfig:"
echo "  export KUBECONFIG=\"$OUTPUT_FILE\""
echo "  kubectl get namespaces"
echo ""
echo "To add to Jenkins:"
echo "  1. Go to Jenkins → Manage Jenkins → Manage Credentials"
echo "  2. Add Credentials → Kubernetes configuration (kubeconfig)"
echo "  3. ID: kubeconfig"
echo "  4. Upload or paste the contents of: $OUTPUT_FILE"
echo ""


