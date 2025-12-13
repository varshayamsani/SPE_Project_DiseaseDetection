# ELK Stack Implementation Documentation

## Table of Contents
1. [Overview](#overview)
2. [Architecture](#architecture)
3. [Components](#components)
4. [File Structure](#file-structure)
5. [Deployment Flow](#deployment-flow)
6. [Log Flow](#log-flow)
7. [Configuration Details](#configuration-details)
8. [Pipeline Integration](#pipeline-integration)
9. [Accessing Logs](#accessing-logs)

---

## Overview

The ELK (Elasticsearch, Logstash, Kibana) stack is implemented as a lightweight, Kubernetes-native logging solution for the Disease Detector application. Instead of using Logstash (which is resource-intensive), we use **Fluentd** as a lightweight log collector.

**Components:**
- **Elasticsearch**: Stores and indexes logs
- **Fluentd**: Collects logs from Kubernetes containers
- **Kibana**: Visualizes and searches logs

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Kubernetes Cluster                        │
│                                                               │
│  ┌──────────────────┐    ┌──────────────────┐               │
│  │  Backend Pod    │    │  Frontend Pod   │               │
│  │  (app.py)       │    │  (nginx)        │               │
│  │                 │    │                 │               │
│  │  stdout/stderr  │    │  stdout/stderr  │               │
│  └────────┬────────┘    └────────┬────────┘               │
│           │                      │                          │
│           │  Container Logs    │                          │
│           │  (/var/log/containers/*.log)                   │
│           │                      │                          │
│           └──────────┬──────────┘                          │
│                      │                                       │
│           ┌─────────▼─────────┐                            │
│           │  Fluentd          │                            │
│           │  DaemonSet         │                            │
│           │  (1 per node)      │                            │
│           │                    │                            │
│           │  - Reads logs      │                            │
│           │  - Parses JSON     │                            │
│           │  - Adds metadata   │                            │
│           └─────────┬─────────┘                            │
│                      │                                       │
│                      │ HTTP/JSON                             │
│           ┌─────────▼─────────┐                            │
│           │  Elasticsearch     │                            │
│           │  Deployment        │                            │
│           │                    │                            │
│           │  - Indexes logs     │                            │
│           │  - Stores data     │                            │
│           └─────────┬─────────┘                            │
│                      │                                       │
│                      │ Query API                             │
│           ┌─────────▼─────────┐                            │
│           │  Kibana           │                            │
│           │  Deployment       │                            │
│           │                    │                            │
│           │  - Visualizes     │                            │
│           │  - Searches       │                            │
│           └───────────────────┘                            │
│                                                               │
└─────────────────────────────────────────────────────────────┘
```

---

## Components

### 1. Elasticsearch
**Purpose**: Distributed search and analytics engine that stores logs

**Key Features:**
- Single-node deployment (lightweight)
- Resource limits: 1Gi memory, 500m CPU
- Persistent storage via PVC
- Exposes service on port 9200

### 2. Fluentd
**Purpose**: Log collector that tails container logs and sends them to Elasticsearch

**Key Features:**
- DaemonSet (runs on every node)
- Resource limits: 256Mi memory, 200m CPU
- Reads from `/var/log/containers/*disease-detector*.log`
- Parses Kubernetes JSON log format
- Adds metadata (pod name, namespace, etc.)

### 3. Kibana
**Purpose**: Web UI for visualizing and searching logs

**Key Features:**
- Single instance deployment
- Resource limits: 1Gi memory, 500m CPU
- Connects to Elasticsearch via service DNS
- Exposes service on port 5601

---

## File Structure

### Kubernetes Manifests

```
k8s/
├── elasticsearch-deployment.yaml    # Elasticsearch deployment and service
├── fluentd-daemonset.yaml          # Fluentd DaemonSet and ConfigMap
├── fluentd-rbac.yaml                # RBAC for Fluentd (ServiceAccount, ClusterRole, ClusterRoleBinding)
└── kibana-deployment.yaml           # Kibana deployment and service
```

### Pipeline Files

```
Jenkinsfile                          # Main CI/CD pipeline (includes ELK deployment stage)
ansible/
└── playbook.yaml                    # Ansible playbook (ELK deployment disabled, handled by Jenkins)
```

### Documentation

```
ELK_IMPLEMENTATION_DOCUMENTATION.md  # This file
KIBANA_LOG_VIEWING_GUIDE.md         # Guide for viewing logs in Kibana
CREATE_KIBANA_INDEX_PATTERN.md      # Guide for creating index patterns
```

---

## File Details

### 1. `k8s/elasticsearch-deployment.yaml`

**What it contains:**
- Elasticsearch Deployment (single replica)
- Elasticsearch Service (ClusterIP, port 9200)
- Resource limits and requests
- Environment variables for single-node mode
- Volume mounts for data persistence

**Key Configuration:**
```yaml
resources:
  requests:
    memory: "512Mi"
    cpu: "500m"
  limits:
    memory: "1Gi"
    cpu: "1"
env:
  - name: discovery.type
    value: "single-node"  # Single-node mode for lightweight deployment
```

**Service:**
- Name: `elasticsearch`
- Type: `ClusterIP`
- Port: `9200`
- Accessible via DNS: `elasticsearch.disease-detector.svc.cluster.local`

---

### 2. `k8s/fluentd-daemonset.yaml`

**What it contains:**
- Fluentd ConfigMap (configuration)
- Fluentd DaemonSet (runs on every node)

**ConfigMap (`fluentd-config`):**
```yaml
<source>
  @type tail
  path /var/log/containers/*disease-detector*.log
  tag disease-detector.*
  <parse>
    @type json
    time_key time
    time_format %Y-%m-%dT%H:%M:%S.%NZ
  </parse>
</source>

<filter disease-detector.**>
  @type record_transformer
  <record>
    message ${record["log"]}
    stream ${record["stream"]}
    log_source "disease-detector"
  </record>
</filter>

<match disease-detector.**>
  @type elasticsearch
  host elasticsearch.disease-detector.svc.cluster.local
  port 9200
  logstash_format true
  logstash_prefix disease-detector-logs
  logstash_dateformat %Y.%m.%d
</match>
```

**DaemonSet Configuration:**
- Image: `fluent/fluentd-kubernetes-daemonset:v1-debian-elasticsearch`
- ServiceAccount: `fluentd` (requires RBAC)
- Volume mounts:
  - `/var/log` (host logs)
  - `/var/lib/docker/containers` (container logs)
  - `/fluentd/etc` (config from ConfigMap)

**Resource Limits:**
```yaml
resources:
  requests:
    memory: "128Mi"
    cpu: "100m"
  limits:
    memory: "256Mi"
    cpu: "200m"
```

---

### 3. `k8s/fluentd-rbac.yaml`

**What it contains:**
- ServiceAccount: `fluentd` (in `disease-detector` namespace)
- ClusterRole: `fluentd-reader` (permissions to read pods and namespaces)
- ClusterRoleBinding: Binds ServiceAccount to ClusterRole

**Why RBAC is needed:**
- Fluentd needs to read pod metadata
- Required for Kubernetes metadata filter (if used)
- Allows Fluentd to enrich logs with pod information

**Permissions:**
```yaml
rules:
- apiGroups: [""]
  resources: ["pods", "namespaces"]
  verbs: ["get", "list", "watch"]
```

---

### 4. `k8s/kibana-deployment.yaml`

**What it contains:**
- Kibana Deployment (single replica)
- Kibana Service (ClusterIP, port 5601)

**Key Configuration:**
```yaml
env:
  - name: ELASTICSEARCH_HOSTS
    value: "http://elasticsearch.disease-detector.svc.cluster.local:9200"
```

**Resource Limits:**
```yaml
resources:
  requests:
    memory: "512Mi"
    cpu: "250m"
  limits:
    memory: "1Gi"
    cpu: "500m"
```

**Service:**
- Name: `kibana`
- Type: `ClusterIP`
- Port: `5601`
- Accessible via: `kubectl port-forward svc/kibana 5601:5601`

---

## Deployment Flow

### Pipeline Execution Order

```
1. Checkout Code
   └─> Git repository cloned

2. Build & Test
   └─> Application built and tested

3. Docker Build
   └─> Backend and Frontend images built

4. Push to Docker Hub
   └─> Images pushed to registry

5. Deploy with Kubernetes (Stage 5)
   └─> Ansible playbook runs
       ├─> Creates namespace
       ├─> Deploys ConfigMaps
       ├─> Deploys Services
       ├─> Deploys Backend Deployment
       ├─> Deploys Frontend Deployment
       └─> ELK deployment SKIPPED (elk_enabled=false)

6. Deploy ELK Stack (Stage 6) ← NEW STAGE
   └─> Jenkins directly applies Kubernetes manifests:
       ├─> kubectl apply elasticsearch-deployment.yaml
       ├─> kubectl apply fluentd-rbac.yaml (if exists)
       ├─> kubectl apply fluentd-daemonset.yaml
       ├─> kubectl apply kibana-deployment.yaml
       └─> Waits for components to be ready

7. Health Check (Stage 7)
   └─> Verifies application health endpoints
```

### Detailed ELK Deployment Steps

**Step 1: Deploy Elasticsearch**
```bash
kubectl apply -f k8s/elasticsearch-deployment.yaml -n disease-detector
```
- Creates Elasticsearch Deployment
- Creates Elasticsearch Service
- Pod starts and initializes
- Waits for `condition=available` (up to 5 minutes)

**Step 2: Deploy Fluentd RBAC**
```bash
kubectl apply -f k8s/fluentd-rbac.yaml -n disease-detector
```
- Creates ServiceAccount `fluentd`
- Creates ClusterRole `fluentd-reader`
- Creates ClusterRoleBinding
- Grants permissions to read pods/namespaces

**Step 3: Deploy Fluentd DaemonSet**
```bash
kubectl apply -f k8s/fluentd-daemonset.yaml -n disease-detector
```
- Creates ConfigMap `fluentd-config`
- Creates DaemonSet `fluentd`
- Fluentd pods start on each node
- Begin tailing container logs

**Step 4: Deploy Kibana**
```bash
kubectl apply -f k8s/kibana-deployment.yaml -n disease-detector
```
- Creates Kibana Deployment
- Creates Kibana Service
- Pod starts and connects to Elasticsearch
- Waits for `condition=available` (up to 5 minutes)

---

## Log Flow

### Step-by-Step Log Journey

**1. Application Generates Log**
```
Backend Pod (app.py)
  └─> logger.info("Prediction request received")
      └─> Outputs to stdout/stderr
```

**2. Kubernetes Captures Log**
```
Container Runtime (Docker/containerd)
  └─> Writes to: /var/log/containers/disease-detector-backend-<pod-id>_disease-detector_backend-<container-id>.log
      └─> Format: {"log":"2025-12-12 15:00:00,123 - root - INFO - Prediction request received\n","stream":"stdout","time":"2025-12-12T15:00:00.123456789Z"}
```

**3. Fluentd Reads Log**
```
Fluentd DaemonSet Pod
  └─> Tails: /var/log/containers/*disease-detector*.log
      └─> Parses JSON format
          └─> Extracts: log, stream, time
              └─> Adds metadata: log_source="disease-detector"
                  └─> Tags: disease-detector.*
```

**4. Fluentd Sends to Elasticsearch**
```
Fluentd Output Plugin
  └─> HTTP POST to: http://elasticsearch.disease-detector.svc.cluster.local:9200
      └─> Index: disease-detector-logs-2025.12.12
          └─> Document:
              {
                "log": "2025-12-12 15:00:00,123 - root - INFO - Prediction request received\n",
                "stream": "stdout",
                "time": "2025-12-12T15:00:00.123456789Z",
                "@timestamp": "2025-12-12T15:00:00.123Z",
                "log_source": "disease-detector"
              }
```

**5. Elasticsearch Stores Log**
```
Elasticsearch
  └─> Indexes document in: disease-detector-logs-2025.12.12
      └─> Makes searchable via API
```

**6. Kibana Queries Elasticsearch**
```
User opens Kibana
  └─> Creates index pattern: disease-detector-*
      └─> Searches logs
          └─> Kibana queries Elasticsearch API
              └─> Displays results in Discover view
```

---

## Configuration Details

### Fluentd Configuration Breakdown

**Source Configuration:**
```yaml
<source>
  @type tail                    # Tail files (like tail -f)
  path /var/log/containers/*disease-detector*.log  # Pattern to match log files
  tag disease-detector.*        # Tag for routing
  read_from_head true           # Read from beginning of file
  <parse>
    @type json                  # Parse as JSON
    time_key time               # Use 'time' field as timestamp
    time_format %Y-%m-%dT%H:%M:%S.%NZ  # ISO8601 format
    keep_time_key true          # Keep original time field
  </parse>
</source>
```

**Filter Configuration:**
```yaml
<filter disease-detector.**>
  @type record_transformer      # Transform log records
  <record>
    message ${record["log"]}    # Extract log message
    stream ${record["stream"]}  # Extract stream (stdout/stderr)
    log_source "disease-detector"  # Add custom field
  </record>
</filter>
```

**Output Configuration:**
```yaml
<match disease-detector.**>
  @type elasticsearch            # Output to Elasticsearch
  host elasticsearch.disease-detector.svc.cluster.local  # Service DNS
  port 9200                      # Elasticsearch port
  logstash_format true          # Use logstash-style index naming
  logstash_prefix disease-detector-logs  # Index prefix
  logstash_dateformat %Y.%m.%d  # Date format in index name
  flush_interval 10s            # Flush every 10 seconds
  <buffer>
    flush_interval 10s          # Buffer flush interval
    retry_type exponential_backoff  # Retry strategy
  </buffer>
</match>
```

### Index Naming Convention

**Pattern:** `disease-detector-logs-YYYY.MM.DD`

**Examples:**
- `disease-detector-logs-2025.12.12` (December 12, 2025)
- `disease-detector-logs-2025.12.13` (December 13, 2025)

**Why daily indices?**
- Easier to manage and delete old logs
- Better performance (smaller indices)
- Aligns with logstash_format convention

---

## Pipeline Integration

### Jenkinsfile Changes

**Environment Variable:**
```groovy
environment {
    DEPLOY_ELK = 'true'  // Set to 'false' to skip ELK deployment
}
```

**New Stage:**
```groovy
stage('Deploy ELK Stack') {
    when {
        expression { 
            return env.DEPLOY_ELK == null || env.DEPLOY_ELK == 'true' || env.DEPLOY_ELK == ''
        }
    }
    steps {
        // Deploys all ELK components
        // Shows progress and waits for readiness
    }
}
```

**Ansible Playbook Update:**
```yaml
# In ansible/playbook.yaml
-e "elk_enabled=false"  # ELK now handled by Jenkins stage
```

### Why Separate Stage?

**Benefits:**
1. **Visibility**: ELK deployment appears as separate stage in pipeline UI
2. **Control**: Can easily skip ELK by setting `DEPLOY_ELK=false`
3. **Debugging**: Easier to see ELK-specific logs and errors
4. **Flexibility**: Can deploy ELK independently if needed

---

## Accessing Logs

### 1. Port-Forward Kibana

```bash
kubectl port-forward -n disease-detector svc/kibana 5601:5601
```

Then open: http://localhost:5601

### 2. Create Index Pattern

1. Go to **Stack Management** → **Index Patterns**
2. Click **Create index pattern**
3. Enter: `disease-detector-*`
4. Select `@timestamp` as time field
5. Click **Create index pattern**

### 3. View Logs in Discover

1. Go to **Discover**
2. Select `disease-detector-*` index pattern
3. Adjust time range (top right)
4. Search logs using KQL syntax

### 4. Useful Searches

```kql
# All prediction requests
log:*Prediction request received*

# All POST requests
log:*POST*

# Backend logs only
log:*werkzeug*

# Specific symptoms
log:*cough*

# Errors
log:*ERROR* OR log:*error*
```

---

## Resource Usage

### Total Resource Requirements

**Elasticsearch:**
- Memory: 1Gi (limit), 512Mi (request)
- CPU: 1 core (limit), 500m (request)

**Fluentd (per node):**
- Memory: 256Mi (limit), 128Mi (request)
- CPU: 200m (limit), 100m (request)

**Kibana:**
- Memory: 1Gi (limit), 512Mi (request)
- CPU: 500m (limit), 250m (request)

**Total (approximate):**
- Memory: ~2.5Gi
- CPU: ~1.75 cores

**Note:** Fluentd runs as DaemonSet, so resource usage scales with number of nodes.

---

## Troubleshooting

### Check Component Status

```bash
# Check all ELK pods
kubectl get pods -n disease-detector -l 'app in (elasticsearch,kibana,fluentd)'

# Check Elasticsearch
kubectl logs -n disease-detector -l app=elasticsearch

# Check Fluentd
kubectl logs -n disease-detector -l app=fluentd

# Check Kibana
kubectl logs -n disease-detector -l app=kibana
```

### Verify Log Flow

```bash
# Check if indices exist
kubectl port-forward -n disease-detector svc/elasticsearch 9200:9200
curl 'http://localhost:9200/_cat/indices?v' | grep disease

# Check document count
curl 'http://localhost:9200/disease-detector-logs-*/_count'

# Search for specific logs
curl 'http://localhost:9200/disease-detector-logs-*/_search?q=log:*Prediction*&size=5&pretty'
```

### Common Issues

**1. No logs appearing in Kibana**
- Check Fluentd is running: `kubectl get daemonset -n disease-detector`
- Check Fluentd logs for errors
- Verify Elasticsearch is accessible from Fluentd
- Check time range in Kibana (may be too narrow)

**2. Fluentd RBAC errors**
- Ensure `fluentd-rbac.yaml` is applied
- Check ServiceAccount exists: `kubectl get sa fluentd -n disease-detector`
- Verify ClusterRoleBinding: `kubectl get clusterrolebinding fluentd-reader`

**3. Elasticsearch connection refused**
- Check Elasticsearch pod is running: `kubectl get pods -l app=elasticsearch`
- Verify service exists: `kubectl get svc elasticsearch -n disease-detector`
- Check DNS resolution: `kubectl run test --image=busybox --rm -it --restart=Never -- nslookup elasticsearch.disease-detector.svc.cluster.local`

---

## Summary

The ELK stack implementation provides:

✅ **Automated deployment** via Jenkins pipeline  
✅ **Lightweight resource usage** (optimized for small clusters)  
✅ **Centralized logging** for all application components  
✅ **Easy log search and visualization** via Kibana  
✅ **Daily index rotation** for efficient log management  
✅ **Kubernetes-native** integration using DaemonSet and Services  

All components are deployed automatically when the pipeline runs, with no manual intervention required.


