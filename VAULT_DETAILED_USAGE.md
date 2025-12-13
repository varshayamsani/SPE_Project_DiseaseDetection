# Vault Detailed Usage Documentation

## Table of Contents
1. [Overview](#overview)
2. [Where Vault is Used](#where-vault-is-used)
3. [File-by-File Breakdown](#file-by-file-breakdown)
4. [Complete Flow](#complete-flow)
5. [Why Vault is Used](#why-vault-is-used)
6. [How to Verify Vault Usage](#how-to-verify-vault-usage)

---

## Overview

**HashiCorp Vault** is used to store and manage **application configuration secrets** for the Disease Detector backend. Vault runs inside the Kubernetes cluster, and the backend pods automatically fetch secrets from Vault at startup.

### What Secrets Are Stored in Vault?

1. **Application Configuration** (`disease-detector/app`):
   - `flask_env`: Flask environment (production/development)
   - `log_level`: Logging level (INFO/DEBUG/WARNING)
   - `elasticsearch_host`: Elasticsearch service hostname
   - `elasticsearch_port`: Elasticsearch port number
   - `database_path`: Database file path
   - `cors_origins`: CORS allowed origins

2. **Database Configuration** (`disease-detector/database`):
   - `path`: Database file path
   - `type`: Database type (sqlite)

### What is NOT Using Vault?

These continue to use Jenkins Credentials Store (as requested):
- ✅ **Docker Hub credentials** - Still in Jenkins Credentials (`credentials('dockerhub')`)
- ✅ **Kubernetes kubeconfig** - Still in Jenkins Credentials (`file(credentialsId: 'kubeconfig')`)

---

## Where Vault is Used

### 1. **Jenkins Pipeline** (Automatic Deployment)
   - **File**: `Jenkinsfile`
   - **Stage**: "Deploy Vault" (Stage 5)
   - **Purpose**: Deploys Vault server and configures secrets automatically

### 2. **Kubernetes Cluster** (Vault Server)
   - **File**: `k8s/vault-deployment.yaml`
   - **Purpose**: Runs Vault server in Kubernetes
   - **Service**: `vault.disease-detector.svc.cluster.local:8200`

### 3. **Vault Configuration** (Secrets Setup)
   - **File**: `k8s/vault-setup-job.yaml`
   - **Purpose**: Kubernetes Job that configures Vault secrets from within the cluster

### 4. **Backend Application** (Secret Consumption)
   - **File**: `k8s/backend-deployment.yaml`
   - **Purpose**: Backend pods fetch secrets from Vault at startup

---

## File-by-File Breakdown

### File 1: `k8s/vault-deployment.yaml`

**Purpose**: Deploys Vault server to Kubernetes

**What it contains:**
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: vault
  namespace: disease-detector
spec:
  replicas: 1
  containers:
  - name: vault
    image: hashicorp/vault:1.15
    args:
    - server
    - -dev                    # Dev mode (no production setup needed)
    - -dev-root-token-id=root-token-12345
    - -dev-listen-address=0.0.0.0:8200
```

**Key Details:**
- **Deployment Name**: `vault`
- **Namespace**: `disease-detector`
- **Image**: `hashicorp/vault:1.15`
- **Mode**: Dev mode (auto-initialized, unsealed)
- **Root Token**: `root-token-12345` (dev mode only)
- **Port**: 8200
- **Service**: `vault` (ClusterIP)

**Why this file exists:**
- Provides Vault server running in Kubernetes
- Accessible via service DNS: `vault.disease-detector.svc.cluster.local:8200`
- No manual setup required (dev mode)

---

### File 2: `k8s/vault-setup-job.yaml`

**Purpose**: Kubernetes Job that configures Vault secrets from within the cluster

**What it contains:**
```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: vault-setup
  namespace: disease-detector
spec:
  template:
    spec:
      containers:
      - name: vault-setup
        image: hashicorp/vault:1.15
        command:
        - /bin/sh
        - -c
        - |
          # Enable KV v2 secrets engine
          vault secrets enable -path=disease-detector kv-v2
          
          # Store application secrets
          vault kv put disease-detector/app \
            flask_env=production \
            log_level=INFO \
            elasticsearch_host=elasticsearch.disease-detector.svc.cluster.local \
            ...
```

**Key Details:**
- **Job Name**: `vault-setup`
- **Runs**: Inside Kubernetes cluster (can access Vault service)
- **Actions**:
  1. Waits for Vault to be ready
  2. Enables KV v2 secrets engine at `disease-detector/`
  3. Stores application config secrets
  4. Stores database config secrets
  5. Creates access policy
- **Auto-cleanup**: Deletes after 5 minutes (TTL)

**Why this file exists:**
- Jenkins cannot access Vault service from outside cluster
- Job runs inside cluster where DNS works
- Automatically configures all secrets

---

### File 3: `k8s/backend-deployment.yaml`

**Purpose**: Backend deployment with Vault integration

**What it contains:**

#### Part A: Init Container (Lines 22-56)
```yaml
initContainers:
- name: vault-init
  image: curlimages/curl:latest
  command:
  - /bin/sh
  - -c
  - |
    # Fetch secrets from Vault
    VAULT_ADDR="http://vault.disease-detector.svc.cluster.local:8200"
    VAULT_TOKEN="root-token-12345"
    
    # Get secrets via Vault API
    RESPONSE=$(curl -s -H "X-Vault-Token: $VAULT_TOKEN" \
      "$VAULT_ADDR/v1/disease-detector/data/app")
    
    # Extract values and write to files
    echo "$RESPONSE" | grep -o '"flask_env":"[^"]*"' | cut -d'"' -f4 > /vault-secrets/FLASK_ENV
    echo "$RESPONSE" | grep -o '"log_level":"[^"]*"' | cut -d'"' -f4 > /vault-secrets/LOG_LEVEL
    ...
```

**What it does:**
1. Runs BEFORE main container starts
2. Connects to Vault service
3. Fetches secrets via Vault API
4. Writes secrets to `/vault-secrets/` volume as individual files:
   - `/vault-secrets/FLASK_ENV`
   - `/vault-secrets/LOG_LEVEL`
   - `/vault-secrets/ELASTICSEARCH_HOST`
   - `/vault-secrets/ELASTICSEARCH_PORT`
   - `/vault-secrets/DATABASE_PATH`
   - `/vault-secrets/CORS_ORIGINS`

#### Part B: Main Container (Lines 57-120)
```yaml
containers:
- name: backend
  command: ["/bin/sh"]
  args:
  - -c
  - |
    # Load secrets from Vault files
    if [ -d "/vault-secrets" ]; then
      export FLASK_ENV=$(cat /vault-secrets/FLASK_ENV 2>/dev/null || echo "production")
      export LOG_LEVEL=$(cat /vault-secrets/LOG_LEVEL 2>/dev/null || echo "INFO")
      export ELASTICSEARCH_HOST=$(cat /vault-secrets/ELASTICSEARCH_HOST 2>/dev/null || echo "elasticsearch.disease-detector.svc.cluster.local")
      ...
    fi
    # Start the application
    exec python app.py
```

**What it does:**
1. Reads secret files from `/vault-secrets/` volume (created by init container)
2. Exports as environment variables
3. Falls back to defaults if Vault secrets not available
4. Starts the Flask application

#### Part C: Volume Mount (Lines 100-110)
```yaml
volumeMounts:
- name: vault-secrets
  mountPath: /vault-secrets
  readOnly: true
volumes:
- name: vault-secrets
  emptyDir: {}
```

**What it does:**
- Creates shared volume between init container and main container
- Init container writes secrets to this volume
- Main container reads from this volume

**Why this file uses Vault:**
- Secrets are fetched from Vault, not hardcoded
- Secrets can be updated in Vault without rebuilding images
- Centralized secret management

---

### File 4: `Jenkinsfile` (Stage 5: Deploy Vault)

**Purpose**: Automatically deploys and configures Vault in the pipeline

**Location**: Lines 107-224

**What it does:**

#### Step 1: Deploy Vault Server (Lines 122-131)
```groovy
echo "📦 Deploying Vault server..."
kubectl apply -f k8s/vault-deployment.yaml -n ${NAMESPACE}

# Wait for Vault to be ready
kubectl wait --for=condition=ready pod -l app=vault -n ${NAMESPACE} --timeout=120s
```

**Why**: Deploys Vault server to Kubernetes before configuring it

#### Step 2: Configure Vault via Job (Lines 137-165)
```groovy
# Delete any existing setup job
kubectl delete job vault-setup -n ${NAMESPACE} --ignore-not-found=true

# Create and run Vault setup job
kubectl apply -f k8s/vault-setup-job.yaml -n ${NAMESPACE}

# Wait for job to complete
kubectl wait --for=condition=complete --timeout=180s job/vault-setup -n ${NAMESPACE}
```

**Why**: 
- Jenkins cannot access Vault service from outside cluster
- Job runs inside cluster where DNS works
- Automatically configures all secrets

**Why this stage exists:**
- Fully automated - no manual steps
- Runs before backend deployment
- Ensures secrets are ready when backend starts

---

### File 5: `vault-setup.sh` (Optional Manual Setup)

**Purpose**: Manual script to configure Vault (if needed)

**Location**: Root directory

**What it does:**
- Initializes Vault (if not already initialized)
- Enables KV v2 secrets engine
- Stores application secrets
- Creates access policies
- Generates application tokens

**When it's used:**
- Manual setup (if automatic setup fails)
- Troubleshooting
- Local development

**Note**: This script is NOT used in the pipeline - the pipeline uses `vault-setup-job.yaml` instead.

---

### File 6: `vault-config.hcl` (Vault Server Configuration)

**Purpose**: Vault server configuration file

**Location**: Root directory

**What it contains:**
```hcl
storage "file" {
  path = "/opt/vault/data"
}

listener "tcp" {
  address = "0.0.0.0:8200"
  tls_disable = 1  # Dev mode only
}
```

**Note**: This file is NOT used in Kubernetes deployment. The `vault-deployment.yaml` uses dev mode which doesn't need this config file.

**When it's used:**
- Local Vault server setup
- Production Vault deployment (not current setup)

---

## Complete Flow

### Flow Diagram

```
┌─────────────────────────────────────────────────────────────┐
│  Jenkins Pipeline (Stage 5: Deploy Vault)                   │
│  File: Jenkinsfile                                          │
└──────────────────┬──────────────────────────────────────────┘
                   │
                   │ 1. Deploy Vault Server
                   ▼
┌─────────────────────────────────────────────────────────────┐
│  Kubernetes Cluster                                         │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐    │
│  │  Vault Deployment                                   │    │
│  │  File: k8s/vault-deployment.yaml                    │    │
│  │  - Pod: vault-xxxxx                                 │    │
│  │  - Service: vault.disease-detector.svc.cluster.local│    │
│  │  - Port: 8200                                       │    │
│  └──────────────────┬──────────────────────────────────┘    │
│                     │                                        │
│                     │ 2. Create Setup Job                    │
│                     ▼                                        │
│  ┌─────────────────────────────────────────────────────┐    │
│  │  Vault Setup Job                                     │    │
│  │  File: k8s/vault-setup-job.yaml                      │    │
│  │  - Connects to Vault service                         │    │
│  │  - Enables KV v2 secrets engine                      │    │
│  │  - Stores secrets:                                   │    │
│  │    * disease-detector/app                            │    │
│  │    * disease-detector/database                       │    │
│  └─────────────────────────────────────────────────────┘    │
│                                                               │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│  Jenkins Pipeline (Stage 6: Deploy with Kubernetes)         │
│  File: Jenkinsfile                                           │
└──────────────────┬──────────────────────────────────────────┘
                   │
                   │ 3. Deploy Backend
                   ▼
┌─────────────────────────────────────────────────────────────┐
│  Kubernetes Cluster                                         │
│                                                               │
│  ┌─────────────────────────────────────────────────────┐    │
│  │  Backend Pod                                        │    │
│  │  File: k8s/backend-deployment.yaml                   │    │
│  │                                                      │    │
│  │  ┌──────────────────────────────────────────────┐  │    │
│  │  │  Init Container (vault-init)                 │  │    │
│  │  │  - Fetches secrets from Vault                │  │    │
│  │  │  - Writes to /vault-secrets/ volume          │  │    │
│  │  └──────────────────┬───────────────────────────┘  │    │
│  │                     │                               │    │
│  │                     │ Shared Volume                 │    │
│  │                     │                               │    │
│  │  ┌──────────────────▼───────────────────────────┐  │    │
│  │  │  Main Container (backend)                   │  │    │
│  │  │  - Reads from /vault-secrets/                │  │    │
│  │  │  - Exports as environment variables         │  │    │
│  │  │  - Starts Flask app                         │  │    │
│  │  └─────────────────────────────────────────────┘  │    │
│  └─────────────────────────────────────────────────────┘    │
│                                                               │
└─────────────────────────────────────────────────────────────┘
```

### Step-by-Step Flow

#### Step 1: Pipeline Starts (Jenkinsfile)
**File**: `Jenkinsfile`  
**Stage**: "Deploy Vault" (Stage 5)  
**Lines**: 107-224

**Actions**:
1. Deploys Vault server: `kubectl apply -f k8s/vault-deployment.yaml`
2. Waits for Vault pod to be ready
3. Creates Vault setup job: `kubectl apply -f k8s/vault-setup-job.yaml`
4. Waits for job to complete
5. Shows job logs
6. Cleans up job

**Why**: Ensures Vault is running and configured before backend deployment

---

#### Step 2: Vault Server Starts (vault-deployment.yaml)
**File**: `k8s/vault-deployment.yaml`  
**Location**: Kubernetes cluster

**Actions**:
1. Vault pod starts with dev mode
2. Auto-initializes (no manual setup needed)
3. Service `vault` is created
4. Accessible at: `vault.disease-detector.svc.cluster.local:8200`

**Why**: Provides Vault server running in Kubernetes

---

#### Step 3: Vault Setup Job Runs (vault-setup-job.yaml)
**File**: `k8s/vault-setup-job.yaml`  
**Location**: Kubernetes cluster (runs as Job)

**Actions**:
1. Waits for Vault API to be ready
2. Enables KV v2 secrets engine at path `disease-detector/`
3. Stores secrets:
   ```bash
   vault kv put disease-detector/app \
     flask_env=production \
     log_level=INFO \
     elasticsearch_host=elasticsearch.disease-detector.svc.cluster.local \
     elasticsearch_port=9200 \
     database_path=/app/data/patients.db \
     cors_origins="http://disease-detector-frontend.disease-detector.svc.cluster.local,http://localhost:3000"
   
   vault kv put disease-detector/database \
     path=/app/data/patients.db \
     type=sqlite
   ```
4. Creates access policy (optional for dev mode)
5. Verifies secrets are stored
6. Job completes and auto-deletes after 5 minutes

**Why**: 
- Jenkins cannot access Vault from outside cluster
- Job runs inside cluster where DNS works
- Automatically configures all secrets

---

#### Step 4: Backend Pod Starts (backend-deployment.yaml)
**File**: `k8s/backend-deployment.yaml`  
**Location**: Kubernetes cluster

**Phase A: Init Container (Lines 23-56)**
1. Init container `vault-init` starts first
2. Connects to Vault: `http://vault.disease-detector.svc.cluster.local:8200`
3. Uses token: `root-token-12345`
4. Fetches secrets via Vault API:
   ```bash
   curl -s -H "X-Vault-Token: root-token-12345" \
     "http://vault.disease-detector.svc.cluster.local:8200/v1/disease-detector/data/app"
   ```
5. Parses JSON response
6. Extracts values and writes to files:
   - `/vault-secrets/FLASK_ENV` → `production`
   - `/vault-secrets/LOG_LEVEL` → `INFO`
   - `/vault-secrets/ELASTICSEARCH_HOST` → `elasticsearch.disease-detector.svc.cluster.local`
   - `/vault-secrets/ELASTICSEARCH_PORT` → `9200`
   - `/vault-secrets/DATABASE_PATH` → `/app/data/patients.db`
   - `/vault-secrets/CORS_ORIGINS` → `http://disease-detector-frontend.disease-detector.svc.cluster.local,http://localhost:3000`
7. Init container completes

**Phase B: Main Container (Lines 57-120)**
1. Main container `backend` starts
2. Reads secret files from `/vault-secrets/` volume
3. Exports as environment variables:
   ```bash
   export FLASK_ENV=$(cat /vault-secrets/FLASK_ENV)
   export LOG_LEVEL=$(cat /vault-secrets/LOG_LEVEL)
   export ELASTICSEARCH_HOST=$(cat /vault-secrets/ELASTICSEARCH_HOST)
   ...
   ```
4. Falls back to defaults if Vault secrets not available
5. Starts Flask application: `exec python app.py`
6. Application uses environment variables (from Vault)

**Why**: 
- Secrets are fetched from Vault, not hardcoded
- Secrets can be updated in Vault without rebuilding images
- Centralized secret management

---

## Why Vault is Used

### 1. **Centralized Secret Management**
- All application secrets in one place
- Easy to update without code changes
- Single source of truth

### 2. **Security**
- Secrets not hardcoded in code
- Secrets not in Docker images
- Secrets not in ConfigMaps (which are base64 encoded, not encrypted)
- Vault encrypts secrets at rest

### 3. **Flexibility**
- Update secrets without redeploying
- Different secrets for different environments
- Secret rotation without downtime

### 4. **Audit Trail**
- Vault logs all secret access
- Know who accessed what secrets when
- Compliance and security auditing

### 5. **Separation of Concerns**
- Application code doesn't need to know secret values
- Secrets managed by operations team
- Developers don't need access to production secrets

---

## How to Verify Vault Usage

### Method 1: Check Vault Pod

```bash
kubectl get pods -n disease-detector -l app=vault
```

**Expected Output:**
```
NAME                     READY   STATUS    RESTARTS   AGE
vault-86685d9868-js7pt   1/1     Running   0          1h
```

**File Involved**: `k8s/vault-deployment.yaml`

---

### Method 2: Check Vault Service

```bash
kubectl get svc -n disease-detector vault
```

**Expected Output:**
```
NAME    TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)    AGE
vault   ClusterIP   10.98.105.16    <none>        8200/TCP   1h
```

**File Involved**: `k8s/vault-deployment.yaml`

---

### Method 3: Check Secrets in Vault

```bash
# Port-forward Vault
kubectl port-forward -n disease-detector svc/vault 8200:8200 &

# Set environment
export VAULT_ADDR="http://localhost:8200"
export VAULT_TOKEN="root-token-12345"

# Get secrets
vault kv get disease-detector/app
vault kv get disease-detector/database
```

**Expected Output:**
```
=== Data ===
Key                  Value
---                  -----
cors_origins         http://disease-detector-frontend.disease-detector.svc.cluster.local,http://localhost:3000
database_path        /app/data/patients.db
elasticsearch_host   elasticsearch.disease-detector.svc.cluster.local
elasticsearch_port   9200
flask_env            production
log_level            INFO
```

**Files Involved**: 
- `k8s/vault-setup-job.yaml` (stores secrets)
- `k8s/vault-deployment.yaml` (provides Vault server)

---

### Method 4: Check Backend Init Container Logs

```bash
POD=$(kubectl get pod -n disease-detector -l app=disease-detector-backend -o jsonpath='{.items[0].metadata.name}')
kubectl logs -n disease-detector $POD -c vault-init
```

**Expected Output:**
```
==========================================
Fetching secrets from Vault...
==========================================
Checking Vault connectivity...
✅ Vault is accessible
Fetching secrets from Vault...

✅ Secrets fetched from Vault:
  FLASK_ENV=production
  LOG_LEVEL=INFO
  ELASTICSEARCH_HOST=elasticsearch.disease-detector.svc.cluster.local
  ELASTICSEARCH_PORT=9200
  DATABASE_PATH=/app/data/patients.db
==========================================
```

**File Involved**: `k8s/backend-deployment.yaml` (init container section)

---

### Method 5: Check Secret Files in Backend Pod

```bash
POD=$(kubectl get pod -n disease-detector -l app=disease-detector-backend -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n disease-detector $POD -- ls -la /vault-secrets/
kubectl exec -n disease-detector $POD -- cat /vault-secrets/FLASK_ENV
kubectl exec -n disease-detector $POD -- cat /vault-secrets/LOG_LEVEL
```

**Expected Output:**
```
-rw-r--r-- 1 root root  9 /vault-secrets/FLASK_ENV
-rw-r--r-- 1 root root  4 /vault-secrets/LOG_LEVEL
-rw-r--r-- 1 root root 50 /vault-secrets/ELASTICSEARCH_HOST
...

production
INFO
```

**File Involved**: `k8s/backend-deployment.yaml` (volume mount section)

---

### Method 6: Check Main Container Logs

```bash
POD=$(kubectl get pod -n disease-detector -l app=disease-detector-backend -o jsonpath='{.items[0].metadata.name}')
kubectl logs -n disease-detector $POD -c backend | grep -i vault
```

**Expected Output:**
```
Loading secrets from Vault...
✅ Using secrets from Vault
  FLASK_ENV=production
  LOG_LEVEL=INFO
  ELASTICSEARCH_HOST=elasticsearch.disease-detector.svc.cluster.local
```

**File Involved**: `k8s/backend-deployment.yaml` (main container command section)

---

### Method 7: Check Environment Variables

```bash
POD=$(kubectl get pod -n disease-detector -l app=disease-detector-backend -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n disease-detector $POD -- env | grep -E "FLASK_ENV|LOG_LEVEL|ELASTICSEARCH"
```

**Expected Output:**
```
FLASK_ENV=production
LOG_LEVEL=INFO
ELASTICSEARCH_HOST=elasticsearch.disease-detector.svc.cluster.local
ELASTICSEARCH_PORT=9200
```

**File Involved**: `k8s/backend-deployment.yaml` (main container command section)

---

### Method 8: Update Secret and Verify Change

```bash
# Update secret in Vault
kubectl port-forward -n disease-detector svc/vault 8200:8200 &
export VAULT_ADDR="http://localhost:8200"
export VAULT_TOKEN="root-token-12345"

vault kv patch disease-detector/app log_level="DEBUG"

# Restart backend to pick up new secret
kubectl rollout restart deployment/disease-detector-backend -n disease-detector

# Wait for new pod
kubectl wait --for=condition=ready pod -l app=disease-detector-backend -n disease-detector --timeout=120s

# Verify new value
POD=$(kubectl get pod -n disease-detector -l app=disease-detector-backend -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n disease-detector $POD -- cat /vault-secrets/LOG_LEVEL
```

**Expected Output:**
```
DEBUG
```

**Files Involved**: 
- `k8s/vault-deployment.yaml` (Vault server)
- `k8s/backend-deployment.yaml` (fetches updated secret)

---

## File Summary

### Files That Use Vault

| File | Purpose | How It Uses Vault |
|------|---------|-------------------|
| `k8s/vault-deployment.yaml` | Deploys Vault server | Defines Vault pod and service |
| `k8s/vault-setup-job.yaml` | Configures Vault secrets | Stores secrets via Vault CLI |
| `k8s/backend-deployment.yaml` | Backend with Vault integration | Init container fetches secrets, main container uses them |
| `Jenkinsfile` (Stage 5) | Automatic Vault deployment | Deploys Vault and runs setup job |

### Files That Reference Vault (But Don't Actively Use It)

| File | Purpose | Status |
|------|---------|--------|
| `vault-setup.sh` | Manual Vault setup script | Optional, for manual setup |
| `vault-config.hcl` | Vault server config | Not used (dev mode doesn't need it) |
| `k8s/vault-agent-config.yaml` | Vault Agent config | Created but not actively used |

---

## Detailed Code Walkthrough

### 1. Vault Deployment (Jenkinsfile Lines 122-131)

```groovy
// Deploy Vault server
kubectl apply -f k8s/vault-deployment.yaml -n ${NAMESPACE}

// Wait for Vault to be ready
kubectl wait --for=condition=ready pod -l app=vault -n ${NAMESPACE} --timeout=120s
```

**What happens:**
1. Applies `k8s/vault-deployment.yaml` to create Vault pod
2. Waits for pod to be in "Ready" state
3. Vault pod starts in dev mode (auto-initialized)

**File**: `Jenkinsfile`  
**Why**: Ensures Vault is running before configuring it

---

### 2. Vault Configuration (Jenkinsfile Lines 137-165)

```groovy
// Create Vault setup job
kubectl apply -f k8s/vault-setup-job.yaml -n ${NAMESPACE}

// Wait for job to complete
kubectl wait --for=condition=complete --timeout=180s job/vault-setup -n ${NAMESPACE}
```

**What happens:**
1. Creates Kubernetes Job from `k8s/vault-setup-job.yaml`
2. Job runs inside cluster (can access Vault service)
3. Job configures Vault secrets
4. Waits for job to complete successfully

**File**: `Jenkinsfile`  
**Why**: Jenkins cannot access Vault from outside cluster, so job runs inside

---

### 3. Vault Setup Job Execution (vault-setup-job.yaml)

```yaml
command:
- /bin/sh
- -c
- |
  vault secrets enable -path=disease-detector kv-v2
  vault kv put disease-detector/app \
    flask_env=production \
    log_level=INFO \
    ...
```

**What happens:**
1. Job pod starts with Vault CLI image
2. Connects to Vault service (internal DNS works)
3. Enables KV v2 secrets engine
4. Stores application secrets
5. Creates access policy
6. Job completes

**File**: `k8s/vault-setup-job.yaml`  
**Why**: Runs inside cluster where Vault service is accessible

---

### 4. Backend Init Container (backend-deployment.yaml Lines 23-56)

```yaml
initContainers:
- name: vault-init
  command:
  - /bin/sh
  - -c
  - |
    VAULT_ADDR="http://vault.disease-detector.svc.cluster.local:8200"
    VAULT_TOKEN="root-token-12345"
    
    RESPONSE=$(curl -s -H "X-Vault-Token: $VAULT_TOKEN" \
      "$VAULT_ADDR/v1/disease-detector/data/app")
    
    echo "$RESPONSE" | grep -o '"flask_env":"[^"]*"' | cut -d'"' -f4 > /vault-secrets/FLASK_ENV
    ...
```

**What happens:**
1. Init container starts before main container
2. Connects to Vault service via internal DNS
3. Fetches secrets using Vault API
4. Parses JSON response
5. Writes secrets to `/vault-secrets/` volume as files
6. Init container completes

**File**: `k8s/backend-deployment.yaml`  
**Why**: Fetches secrets from Vault and makes them available to main container

---

### 5. Backend Main Container (backend-deployment.yaml Lines 57-120)

```yaml
containers:
- name: backend
  command: ["/bin/sh"]
  args:
  - -c
  - |
    if [ -d "/vault-secrets" ]; then
      export FLASK_ENV=$(cat /vault-secrets/FLASK_ENV)
      export LOG_LEVEL=$(cat /vault-secrets/LOG_LEVEL)
      ...
    fi
    exec python app.py
```

**What happens:**
1. Main container starts after init container completes
2. Reads secret files from `/vault-secrets/` volume
3. Exports as environment variables
4. Falls back to defaults if Vault secrets not available
5. Starts Flask application
6. Application uses environment variables (from Vault)

**File**: `k8s/backend-deployment.yaml`  
**Why**: Uses secrets from Vault instead of hardcoded values

---

## Why Each Component Exists

### Why Vault Server (vault-deployment.yaml)?

**Purpose**: Provides Vault server running in Kubernetes

**Why needed**:
- Centralized secret storage
- Encrypted at rest
- Access control and audit logging
- Secret rotation capabilities

**Alternative**: Could use Kubernetes Secrets, but:
- Kubernetes Secrets are base64 encoded (not encrypted)
- Harder to rotate
- No audit trail
- No centralized management

---

### Why Vault Setup Job (vault-setup-job.yaml)?

**Purpose**: Configures Vault secrets from within the cluster

**Why needed**:
- Jenkins runs outside cluster (cannot access Vault service DNS)
- Job runs inside cluster (can access Vault service)
- Automates secret configuration
- No manual intervention required

**Alternative**: Could configure manually, but:
- Requires manual steps
- Not automated
- Error-prone

---

### Why Init Container in Backend (backend-deployment.yaml)?

**Purpose**: Fetches secrets from Vault before main container starts

**Why needed**:
- Secrets available before application starts
- Application doesn't need Vault client library
- Secrets as files (simple to use)
- Fallback to defaults if Vault unavailable

**Alternative**: Could use Vault Agent sidecar, but:
- More complex
- Requires additional configuration
- Init container is simpler for this use case

---

### Why Jenkins Stage (Jenkinsfile)?

**Purpose**: Automatically deploys and configures Vault

**Why needed**:
- Fully automated pipeline
- No manual steps required
- Ensures Vault is ready before backend deployment
- Consistent setup every time

**Alternative**: Could deploy manually, but:
- Requires manual intervention
- Inconsistent
- Error-prone

---

## Secret Flow Diagram

```
┌─────────────────────────────────────────────────────────────┐
│  Vault Server                                               │
│  (vault.disease-detector.svc.cluster.local:8200)           │
│                                                               │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  KV v2 Secrets Engine                                │   │
│  │  Path: disease-detector/                             │   │
│  │                                                       │   │
│  │  ┌───────────────────────────────────────────────┐   │   │
│  │  │  Secret: disease-detector/app                 │   │   │
│  │  │  - flask_env: production                     │   │   │
│  │  │  - log_level: INFO                           │   │   │
│  │  │  - elasticsearch_host: ...                    │   │   │
│  │  │  - elasticsearch_port: 9200                   │   │   │
│  │  │  - database_path: /app/data/patients.db      │   │   │
│  │  │  - cors_origins: ...                         │   │   │
│  │  └───────────────────────────────────────────────┘   │   │
│  │                                                       │   │
│  │  ┌───────────────────────────────────────────────┐   │   │
│  │  │  Secret: disease-detector/database            │   │   │
│  │  │  - path: /app/data/patients.db                │   │   │
│  │  │  - type: sqlite                               │   │   │
│  │  └───────────────────────────────────────────────┘   │   │
│  └─────────────────────────────────────────────────────┘   │
└───────────────────┬─────────────────────────────────────────┘
                    │
                    │ HTTP API Request
                    │ X-Vault-Token: root-token-12345
                    │
                    ▼
┌─────────────────────────────────────────────────────────────┐
│  Backend Pod Init Container                                  │
│  (vault-init)                                                │
│                                                               │
│  1. curl http://vault.../v1/disease-detector/data/app       │
│  2. Parse JSON response                                      │
│  3. Write to /vault-secrets/ volume:                        │
│     - FLASK_ENV → production                                 │
│     - LOG_LEVEL → INFO                                       │
│     - ELASTICSEARCH_HOST → ...                              │
│     - ...                                                    │
└───────────────────┬─────────────────────────────────────────┘
                    │
                    │ Shared Volume
                    │ /vault-secrets/
                    │
                    ▼
┌─────────────────────────────────────────────────────────────┐
│  Backend Pod Main Container                                  │
│  (backend)                                                    │
│                                                               │
│  1. Read from /vault-secrets/ volume                        │
│  2. Export as environment variables:                        │
│     export FLASK_ENV=$(cat /vault-secrets/FLASK_ENV)        │
│     export LOG_LEVEL=$(cat /vault-secrets/LOG_LEVEL)        │
│     ...                                                      │
│  3. Start Flask application                                 │
│  4. Application uses environment variables                   │
└─────────────────────────────────────────────────────────────┘
```

---

## Summary

### Where Vault is Used

1. **Jenkins Pipeline** (`Jenkinsfile`):
   - Stage 5: Deploys Vault server
   - Stage 5: Configures Vault secrets via Job
   - Runs automatically on every pipeline execution

2. **Kubernetes Cluster**:
   - Vault server pod (`k8s/vault-deployment.yaml`)
   - Vault setup job (`k8s/vault-setup-job.yaml`)
   - Backend pods with Vault integration (`k8s/backend-deployment.yaml`)

3. **Backend Application**:
   - Init container fetches secrets from Vault
   - Main container uses secrets as environment variables
   - Application reads from environment variables

### What Secrets Are Managed

- Application configuration (Flask env, log level, Elasticsearch config)
- Database configuration
- CORS settings

### What is NOT Using Vault

- Docker Hub credentials → Jenkins Credentials Store
- Kubernetes kubeconfig → Jenkins Credentials Store

### Key Files

1. `k8s/vault-deployment.yaml` - Vault server
2. `k8s/vault-setup-job.yaml` - Secret configuration
3. `k8s/backend-deployment.yaml` - Backend with Vault integration
4. `Jenkinsfile` - Automatic deployment

**Everything is fully automated - no manual steps required!**

