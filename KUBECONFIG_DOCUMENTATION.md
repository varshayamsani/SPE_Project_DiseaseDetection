# Kubeconfig Documentation for Jenkins

## Table of Contents
1. [Overview](#overview)
2. [What is Kubeconfig?](#what-is-kubeconfig)
3. [Why Use Kubeconfig?](#why-use-kubeconfig)
4. [Kubeconfig Structure](#kubeconfig-structure)
5. [Jenkins Kubeconfig Setup](#jenkins-kubeconfig-setup)
6. [Generation Process](#generation-process)
7. [Security Considerations](#security-considerations)
8. [File Flow](#file-flow)
9. [Troubleshooting](#troubleshooting)

---

## Overview

Kubeconfig is a configuration file that tells `kubectl` (and other Kubernetes tools) how to connect to and authenticate with a Kubernetes cluster. In our setup, we use a **service account-based kubeconfig** that allows Jenkins to securely deploy applications to Kubernetes without using your personal credentials.

---

## What is Kubeconfig?

**Kubeconfig** is a YAML file that contains:
- **Cluster information**: Where the Kubernetes API server is located
- **Authentication credentials**: How to prove your identity
- **Context**: Which cluster, user, and namespace to use
- **Current context**: Which context is active

Think of it as a "key" that unlocks access to your Kubernetes cluster.

---

## Why Use Kubeconfig?

### 1. **Security**
- **Separation of concerns**: Jenkins doesn't use your personal credentials
- **Least privilege**: Service account has only the permissions it needs
- **Audit trail**: All actions are logged with the service account identity
- **Token rotation**: Tokens can be rotated without affecting your personal access

### 2. **Automation**
- **CI/CD pipelines**: Jenkins can deploy without manual intervention
- **No human credentials**: No need to store personal passwords/tokens
- **Scalable**: Multiple Jenkins jobs can use the same service account

### 3. **Best Practices**
- **Service accounts**: Recommended way for applications to access Kubernetes
- **RBAC**: Fine-grained permissions via Role-Based Access Control
- **Namespace isolation**: Can restrict access to specific namespaces

---

## Kubeconfig Structure

### Complete Kubeconfig File Structure

```yaml
apiVersion: v1
kind: Config

# Cluster Configuration
clusters:
- cluster:
    server: https://127.0.0.1:54655          # Kubernetes API server URL
    certificate-authority-data: LS0tLS1C...  # Base64-encoded CA certificate
  name: minikube                             # Cluster name

# Context Configuration (combines cluster + user + namespace)
contexts:
- context:
    cluster: minikube                        # Which cluster to use
    namespace: disease-detector              # Default namespace
    user: jenkins-service-account            # Which user/credentials
  name: jenkins-context                      # Context name

# Current Context (which context is active)
current-context: jenkins-context

# User/Authentication Configuration
users:
- name: jenkins-service-account
  user:
    token: eyJhbGciOiJSUzI1NiIsImtpZCI6...  # Service account token
```

### Component Breakdown

#### 1. **Clusters Section**
```yaml
clusters:
- cluster:
    server: https://127.0.0.1:54655
    certificate-authority-data: <base64-encoded-ca-cert>
  name: minikube
```

**What it contains:**
- `server`: The URL of the Kubernetes API server
- `certificate-authority-data`: The CA certificate used to verify the API server's TLS certificate (base64-encoded)
- `name`: A friendly name for this cluster

**Why it's needed:**
- Tells `kubectl` where to connect
- Ensures secure TLS connection (verifies server identity)

#### 2. **Contexts Section**
```yaml
contexts:
- context:
    cluster: minikube
    namespace: disease-detector
    user: jenkins-service-account
  name: jenkins-context
```

**What it contains:**
- `cluster`: Which cluster to use (references name from clusters section)
- `namespace`: Default namespace for commands
- `user`: Which credentials to use (references name from users section)
- `name`: A friendly name for this context

**Why it's needed:**
- Combines cluster, user, and namespace into one "context"
- Allows switching between different environments easily

#### 3. **Users Section**
```yaml
users:
- name: jenkins-service-account
  user:
    token: eyJhbGciOiJSUzI1NiIsImtpZCI6...
```

**What it contains:**
- `name`: Name of the user/identity
- `token`: Service account token (JWT) for authentication

**Why it's needed:**
- Provides authentication credentials
- Service account token proves identity to Kubernetes API

#### 4. **Current Context**
```yaml
current-context: jenkins-context
```

**What it contains:**
- Which context is currently active

**Why it's needed:**
- `kubectl` uses this context by default
- Can be overridden with `--context` flag

---

## Jenkins Kubeconfig Setup

### Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Kubernetes Cluster                        │
│                                                               │
│  ┌─────────────────────────────────────────────────────┐    │
│  │  Service Account: jenkins-service-account          │    │
│  │  Namespace: disease-detector                       │    │
│  │                                                     │    │
│  │  ┌─────────────────────────────────────────────┐  │    │
│  │  │  Secret: jenkins-service-account-token      │  │    │
│  │  │  Contains: Token, CA cert                    │  │    │
│  │  └─────────────────────────────────────────────┘  │    │
│  └─────────────────────────────────────────────────────┘    │
│                      │                                       │
│                      │ RBAC                                  │
│                      │                                       │
│  ┌──────────────────▼──────────────────────────────────┐   │
│  │  ClusterRole: jenkins-deployer                      │   │
│  │  Permissions:                                       │   │
│  │    - Create/update deployments                     │   │
│  │    - Create/update services                         │   │
│  │    - Read pods, namespaces                          │   │
│  │    - Manage ConfigMaps, PVCs                        │   │
│  └──────────────────────────────────────────────────────┘   │
│                                                               │
└─────────────────────────────────────────────────────────────┘
                      ▲
                      │
                      │ kubeconfig file
                      │
┌─────────────────────┴─────────────────────────────────────┐
│                    Jenkins Server                          │
│                                                             │
│  ┌───────────────────────────────────────────────────┐     │
│  │  Credentials Store                                │     │
│  │  ID: kubeconfig                                   │     │
│  │  Type: Secret file                                │     │
│  │  Content: jenkins-kubeconfig.yaml                 │     │
│  └───────────────────────────────────────────────────┘     │
│                      │                                       │
│                      │ Used in pipeline                      │
│                      │                                       │
│  ┌───────────────────▼───────────────────────────────────┐  │
│  │  Jenkins Pipeline (Jenkinsfile)                     │  │
│  │                                                       │  │
│  │  withCredentials([                                   │  │
│  │    file(credentialsId: 'kubeconfig',                │  │
│  │         variable: 'KUBECONFIG_FILE')                 │  │
│  │  ]) {                                                │  │
│  │    export KUBECONFIG="$KUBECONFIG_FILE"             │  │
│  │    kubectl apply -f ...                              │  │
│  │  }                                                    │  │
│  └───────────────────────────────────────────────────────┘  │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

## Generation Process

### Step-by-Step: How `jenkins-kubeconfig.yaml` is Created

#### File: `scripts/create-jenkins-kubeconfig.sh`

**Step 1: Verify Service Account Exists**
```bash
kubectl get serviceaccount jenkins-service-account -n disease-detector
```
- Checks if service account exists
- If not, applies `k8s/jenkins-service.yaml` to create it
- Waits for Kubernetes to create the associated secret

**Step 2: Get Cluster Information**
```bash
# Get cluster URL
CLUSTER_URL=$(kubectl cluster-info | grep "Kubernetes control plane" | awk '{print $NF}')

# Get cluster name
CLUSTER_NAME=$(kubectl config view --raw -o jsonpath='{.clusters[0].name}')
```
- Retrieves the Kubernetes API server URL (e.g., `https://127.0.0.1:54655`)
- Gets the cluster name from current kubeconfig

**Step 3: Get CA Certificate**
```bash
# Try to get from current kubeconfig
CA_DATA=$(kubectl config view --minify --raw -o jsonpath='{.clusters[0].cluster.certificate-authority-data}')

# If not found, read from minikube CA file
if [ -z "$CA_DATA" ]; then
    CA_DATA=$(cat ~/.minikube/ca.crt | base64 | tr -d '\n')
fi
```
- Retrieves the cluster's CA certificate
- Used to verify TLS connection to API server
- Base64-encodes the certificate for kubeconfig format

**Step 4: Create Service Account Token**
```bash
TOKEN=$(kubectl create token jenkins-service-account \
    -n disease-detector \
    --duration=8760h \
    --request-timeout=30s)
```
- Creates a new token for the service account
- Token duration: 10 years (8760 hours) - for long-term CI/CD use
- Token is a JWT that proves identity to Kubernetes API

**Step 5: Generate Kubeconfig File**
```bash
cat > jenkins-kubeconfig.yaml <<EOF
apiVersion: v1
kind: Config
clusters:
- cluster:
    server: $CLUSTER_URL
    certificate-authority-data: $CA_DATA
  name: $CLUSTER_NAME
contexts:
- context:
    cluster: $CLUSTER_NAME
    namespace: disease-detector
    user: jenkins-service-account
  name: jenkins-context
current-context: jenkins-context
users:
- name: jenkins-service-account
  user:
    token: $TOKEN
EOF
```
- Combines all information into a kubeconfig file
- Sets default namespace to `disease-detector`
- Uses service account token for authentication

**Step 6: Verify Kubeconfig**
```bash
KUBECONFIG="jenkins-kubeconfig.yaml" kubectl cluster-info
KUBECONFIG="jenkins-kubeconfig.yaml" kubectl get namespaces
```
- Tests the kubeconfig file
- Verifies it can connect to the cluster
- Confirms authentication works

---

## Why Store in Jenkins Secrets?

### Security Benefits

1. **Encrypted Storage**
   - Jenkins encrypts credentials at rest
   - Only Jenkins can decrypt and use them
   - Not visible in pipeline logs (when used correctly)

2. **Access Control**
   - Only authorized Jenkins users can view/modify credentials
   - Can be restricted to specific jobs/pipelines
   - Audit trail of who accessed credentials

3. **No Hardcoding**
   - Credentials not stored in code repository
   - Can be rotated without code changes
   - Different credentials for different environments

4. **Secret Masking**
   - Jenkins automatically masks secrets in console output
   - Prevents accidental exposure in logs
   - Reduces risk of credential leakage

### How Jenkins Uses It

**In Jenkinsfile:**
```groovy
withCredentials([file(credentialsId: 'kubeconfig', variable: 'KUBECONFIG_FILE')]) {
    sh '''
        export KUBECONFIG="$KUBECONFIG_FILE"
        kubectl apply -f k8s/backend-deployment.yaml
    '''
}
```

**What happens:**
1. Jenkins retrieves the kubeconfig file from credentials store
2. Writes it to a temporary file (path stored in `KUBECONFIG_FILE`)
3. Pipeline uses this file via `export KUBECONFIG=...`
4. After pipeline completes, temporary file is deleted
5. Secret is masked in console output

---

## File Flow

### Complete Flow Diagram

```
┌─────────────────────────────────────────────────────────────┐
│ Step 1: Create Service Account & RBAC                       │
│                                                               │
│  kubectl apply -f k8s/jenkins-service.yaml                  │
│                                                               │
│  Creates:                                                     │
│  ├── ServiceAccount: jenkins-service-account                │
│  ├── ClusterRole: jenkins-deployer                          │
│  ├── ClusterRoleBinding: jenkins-deployer-binding           │
│  └── Secret: jenkins-service-account-token                  │
│                                                               │
└─────────────────────────────────────────────────────────────┘
                      │
                      │
                      ▼
┌─────────────────────────────────────────────────────────────┐
│ Step 2: Generate Kubeconfig                                 │
│                                                               │
│  ./scripts/create-jenkins-kubeconfig.sh                      │
│                                                               │
│  Script does:                                                 │
│  1. Gets cluster URL (from kubectl cluster-info)           │
│  2. Gets CA certificate (from ~/.minikube/ca.crt)          │
│  3. Creates service account token (kubectl create token)    │
│  4. Generates jenkins-kubeconfig.yaml                       │
│                                                               │
│  Output: jenkins-kubeconfig.yaml                             │
│                                                               │
└─────────────────────────────────────────────────────────────┘
                      │
                      │
                      ▼
┌─────────────────────────────────────────────────────────────┐
│ Step 3: Add to Jenkins Credentials Store                    │
│                                                               │
│  Jenkins UI:                                                  │
│  Manage Jenkins → Manage Credentials → Add Credentials     │
│                                                               │
│  Configuration:                                               │
│  ├── Kind: Secret file                                       │
│  ├── ID: kubeconfig                                          │
│  ├── File: jenkins-kubeconfig.yaml                           │
│  └── Description: Kubernetes cluster kubeconfig              │
│                                                               │
│  Result: Stored encrypted in Jenkins                         │
│                                                               │
└─────────────────────────────────────────────────────────────┘
                      │
                      │
                      ▼
┌─────────────────────────────────────────────────────────────┐
│ Step 4: Use in Pipeline                                       │
│                                                               │
│  Jenkinsfile:                                                 │
│                                                               │
│  withCredentials([                                            │
│    file(credentialsId: 'kubeconfig',                        │
│         variable: 'KUBECONFIG_FILE')                        │
│  ]) {                                                         │
│    sh '''                                                     │
│      export KUBECONFIG="$KUBECONFIG_FILE"                    │
│      kubectl apply -f k8s/backend-deployment.yaml            │
│    '''                                                        │
│  }                                                            │
│                                                               │
│  What happens:                                                │
│  1. Jenkins retrieves kubeconfig from credentials store     │
│  2. Writes to temp file (e.g., /tmp/kubeconfig123)           │
│  3. Sets KUBECONFIG_FILE=/tmp/kubeconfig123                  │
│  4. Pipeline uses it via export KUBECONFIG=...              │
│  5. kubectl authenticates using service account token        │
│  6. Kubernetes API verifies token and checks RBAC           │
│  7. Request is authorized (if permissions allow)            │
│  8. Temp file deleted after pipeline completes              │
│                                                               │
└─────────────────────────────────────────────────────────────┘
```

---

## Security Considerations

### 1. **Service Account vs Personal Credentials**

**Service Account (What we use):**
- ✅ Limited permissions (only what's needed)
- ✅ Can be rotated without affecting personal access
- ✅ Audit trail shows service account actions
- ✅ Can be revoked independently

**Personal Credentials:**
- ❌ Full user permissions (often too broad)
- ❌ Rotation affects personal access
- ❌ Harder to audit (mixed with personal actions)
- ❌ Security risk if compromised

### 2. **RBAC Permissions**

**What Jenkins Can Do:**
```yaml
# From k8s/jenkins-service.yaml
rules:
  - resources: ["deployments", "services", "pods", "configmaps"]
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
```

**What Jenkins Cannot Do:**
- ❌ Delete namespaces
- ❌ Modify cluster-level resources
- ❌ Access other namespaces (unless explicitly allowed)
- ❌ Escalate privileges

### 3. **Token Security**

**Token Characteristics:**
- **Type**: JWT (JSON Web Token)
- **Duration**: 10 years (8760 hours)
- **Scope**: Only for the service account
- **Revocable**: Can be rotated/revoked anytime

**Best Practices:**
- ✅ Store in Jenkins credentials (encrypted)
- ✅ Never commit to git repository
- ✅ Rotate periodically (even if long-lived)
- ✅ Monitor for unauthorized use

### 4. **TLS Certificate Verification**

**Certificate Authority (CA):**
- Used to verify API server identity
- Prevents man-in-the-middle attacks
- Base64-encoded in kubeconfig

**Insecure Mode (Development Only):**
```yaml
clusters:
- cluster:
    insecure-skip-tls-verify: true  # ⚠️ Only for dev/testing
```

---

## File Reference

### Key Files

| File | Purpose | Location |
|------|---------|----------|
| `k8s/jenkins-service.yaml` | Creates ServiceAccount, ClusterRole, ClusterRoleBinding | Kubernetes manifest |
| `scripts/create-jenkins-kubeconfig.sh` | Generates kubeconfig file | Generation script |
| `jenkins-kubeconfig.yaml` | Generated kubeconfig file | Output file |
| `Jenkinsfile` | Uses kubeconfig in pipeline | Pipeline definition |

### File Contents Breakdown

#### `k8s/jenkins-service.yaml`
```yaml
# Service Account
apiVersion: v1
kind: ServiceAccount
metadata:
  name: jenkins-service-account
  namespace: disease-detector

# ClusterRole (permissions)
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: jenkins-deployer
rules:
  - apiGroups: [""]
    resources: ["deployments", "services", "pods"]
    verbs: ["get", "list", "create", "update", "delete"]

# ClusterRoleBinding (grants permissions)
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: jenkins-deployer-binding
roleRef:
  kind: ClusterRole
  name: jenkins-deployer
subjects:
  - kind: ServiceAccount
    name: jenkins-service-account
    namespace: disease-detector
```

#### `scripts/create-jenkins-kubeconfig.sh`
- **Lines 1-24**: Script setup and service account check
- **Lines 26-44**: Get cluster URL and name
- **Lines 46-70**: Get CA certificate
- **Lines 72-100**: Create service account token
- **Lines 102-135**: Generate kubeconfig file
- **Lines 137-167**: Verify and display instructions

#### Generated `jenkins-kubeconfig.yaml`
- Contains cluster URL, CA cert, token, context
- Ready to use with `kubectl`
- Should be added to Jenkins credentials store

---

## Troubleshooting

### Common Issues

#### 1. **"the server has asked for the client to provide credentials"**

**Cause:** Invalid or expired token

**Solution:**
```bash
# Regenerate kubeconfig
./scripts/create-jenkins-kubeconfig.sh

# Update Jenkins credentials with new file
```

#### 2. **"TLS handshake timeout"**

**Cause:** Cluster URL incorrect or unreachable

**Solution:**
```bash
# Check cluster is running
kubectl cluster-info

# Update kubeconfig with correct URL
./scripts/fix-kubeconfig-for-jenkins.sh
```

#### 3. **"Forbidden" errors**

**Cause:** Service account lacks permissions

**Solution:**
```bash
# Verify RBAC is applied
kubectl get clusterrolebinding jenkins-deployer-binding

# Reapply if needed
kubectl apply -f k8s/jenkins-service.yaml
```

#### 4. **"certificate signed by unknown authority"**

**Cause:** CA certificate missing or incorrect

**Solution:**
```bash
# Regenerate with correct CA cert
./scripts/create-jenkins-kubeconfig.sh

# Or use insecure version (dev only)
./scripts/create-jenkins-kubeconfig-insecure.sh
```

### Verification Commands

```bash
# Test kubeconfig locally
export KUBECONFIG=jenkins-kubeconfig.yaml
kubectl cluster-info
kubectl get namespaces
kubectl get pods -n disease-detector

# Check service account
kubectl get serviceaccount jenkins-service-account -n disease-detector

# Check RBAC
kubectl get clusterrole jenkins-deployer
kubectl get clusterrolebinding jenkins-deployer-binding

# Test permissions
kubectl auth can-i create deployments --as=system:serviceaccount:disease-detector:jenkins-service-account
```

---

## Summary

### Key Takeaways

1. **Kubeconfig** = Configuration file for Kubernetes access
2. **Service Account** = Identity for Jenkins (not personal credentials)
3. **RBAC** = Permissions granted to service account
4. **Jenkins Secrets** = Secure storage for kubeconfig
5. **Generation Script** = Creates kubeconfig automatically

### Why This Setup?

✅ **Secure**: Service account with limited permissions  
✅ **Automated**: Script generates kubeconfig  
✅ **Maintainable**: Easy to rotate tokens  
✅ **Auditable**: All actions logged with service account  
✅ **Best Practice**: Recommended approach for CI/CD  

### Workflow Summary

```
1. Create Service Account & RBAC (k8s/jenkins-service.yaml)
   ↓
2. Generate Kubeconfig (scripts/create-jenkins-kubeconfig.sh)
   ↓
3. Store in Jenkins Credentials (Jenkins UI)
   ↓
4. Use in Pipeline (Jenkinsfile withCredentials)
   ↓
5. Jenkins deploys to Kubernetes (authenticated via service account)
```

This setup ensures Jenkins can deploy to Kubernetes securely and automatically, without requiring personal credentials or manual intervention.


