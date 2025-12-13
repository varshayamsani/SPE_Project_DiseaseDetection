# Canary Deployment Documentation

## Table of Contents
1. [Overview](#overview)
2. [What is Canary Deployment?](#what-is-canary-deployment)
3. [Canary vs Live Patching](#canary-vs-live-patching)
4. [Architecture](#architecture)
5. [File Structure](#file-structure)
6. [How It Works](#how-it-works)
7. [Deployment Strategy](#deployment-strategy)
8. [Traffic Routing](#traffic-routing)
9. [Monitoring & Rollback](#monitoring--rollback)
10. [Implementation Details](#implementation-details)
11. [Usage Examples](#usage-examples)

---

## Overview

Canary deployment is a **gradual rollout strategy** that allows you to test new versions of your application in production with a small percentage of real users before fully deploying. It's named after the "canary in a coal mine" concept - using a small test group to detect problems before they affect everyone.

**Key Characteristics:**
- ✅ Zero-downtime deployments
- ✅ Gradual traffic shift (10% → 25% → 50% → 75% → 100%)
- ✅ Automatic rollback on failure
- ✅ Production testing with real traffic
- ✅ Early detection of issues

---

## What is Canary Deployment?

### Definition

**Canary Deployment** is a deployment strategy where:
1. A new version is deployed alongside the existing stable version
2. A small percentage of traffic is routed to the new version
3. The new version is monitored for issues
4. If successful, traffic is gradually increased
5. If problems are detected, traffic is automatically rolled back to the stable version

### Why Use Canary Deployment?

**Benefits:**
- **Risk Reduction**: Catch issues before they affect all users
- **Production Testing**: Test with real traffic and real data
- **Gradual Rollout**: Minimize impact of potential bugs
- **Automatic Rollback**: Revert quickly if problems occur
- **Zero Downtime**: No service interruption during deployment
- **Confidence**: Validate changes in production before full rollout

**Use Cases:**
- Deploying new features
- Updating ML models
- Performance optimizations
- Bug fixes
- Infrastructure changes

---

## Canary vs Live Patching

### Are They the Same?

**No, they are different concepts:**

| Aspect | Canary Deployment | Live Patching |
|--------|------------------|---------------|
| **What it is** | Gradual rollout strategy | Hot-fix without restart |
| **How it works** | Deploy new version alongside old | Patch running process in memory |
| **Traffic** | Split traffic between versions | All traffic to patched version |
| **Rollback** | Route traffic back to stable | Revert patch or restart |
| **Use case** | New features, major updates | Critical security fixes |
| **Complexity** | Medium (requires orchestration) | High (requires special tools) |
| **Risk** | Low (gradual rollout) | Medium (immediate change) |
| **Downtime** | Zero | Zero (if done correctly) |

### Key Differences

#### Canary Deployment
```
┌─────────────────────────────────────────┐
│  All Users                              │
│  ┌──────────┐  ┌──────────┐            │
│  │ Stable   │  │ Canary   │            │
│  │ (90%)    │  │ (10%)    │            │
│  └──────────┘  └──────────┘            │
│       │              │                  │
│       └──────┬───────┘                  │
│              │                          │
│         Load Balancer                   │
└─────────────────────────────────────────┘
```

**Characteristics:**
- Two versions run simultaneously
- Traffic split between versions
- Gradual increase of canary traffic
- Can rollback by routing traffic away from canary

#### Live Patching
```
┌─────────────────────────────────────────┐
│  Running Process                        │
│  ┌──────────────────────────┐          │
│  │  Original Code            │          │
│  │  ┌────────────────────┐  │          │
│  │  │  Patched Code      │  │          │
│  │  │  (in memory)       │  │          │
│  │  └────────────────────┘  │          │
│  └──────────────────────────┘          │
│         │                                │
│    No Restart                            │
└─────────────────────────────────────────┘
```

**Characteristics:**
- Single running process
- Code patched in memory
- No restart required
- Immediate effect
- Requires special patching tools (e.g., kpatch, livepatch)

### When to Use Each

**Use Canary Deployment when:**
- ✅ Deploying new features
- ✅ Updating application code
- ✅ Testing ML models
- ✅ Major version updates
- ✅ You want gradual rollout

**Use Live Patching when:**
- ✅ Critical security fixes
- ✅ Kernel-level patches
- ✅ Cannot restart the service
- ✅ Emergency hot-fixes
- ✅ You have live patching infrastructure

---

## Architecture

### Canary Deployment Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Kubernetes Cluster                        │
│                                                               │
│  ┌─────────────────────────────────────────────────────┐    │
│  │  Load Balancer / Service                            │    │
│  │  Routes traffic based on weight                     │    │
│  └──────────────┬──────────────────┬───────────────────┘    │
│                 │                  │                         │
│                 │ 90% traffic      │ 10% traffic             │
│                 │                  │                         │
│  ┌──────────────▼──────────┐  ┌───▼──────────────────────┐ │
│  │  Stable Deployment      │  │  Canary Deployment      │ │
│  │  (3 replicas)           │  │  (1 replica)            │ │
│  │                         │  │                         │ │
│  │  Image: v1.0            │  │  Image: v1.1            │ │
│  │  Service: stable        │  │  Service: canary        │ │
│  │                         │  │                         │ │
│  │  ┌────┐  ┌────┐  ┌────┐│  │  ┌────┐                │ │
│  │  │Pod │  │Pod │  │Pod ││  │  │Pod │                │ │
│  │  └────┘  └────┘  └────┘│  │  └────┘                │ │
│  └─────────────────────────┘  └─────────────────────────┘ │
│                                                               │
│  ┌─────────────────────────────────────────────────────┐    │
│  │  Monitoring & Analysis                              │    │
│  │  - Success rate                                      │    │
│  │  - Error rate                                        │    │
│  │  - Response time                                     │    │
│  │  - Resource usage                                    │    │
│  └─────────────────────────────────────────────────────┘    │
│                                                               │
└─────────────────────────────────────────────────────────────┘
```

### Traffic Flow

```
User Request
    │
    ▼
Load Balancer / Service
    │
    ├─── 90% ────► Stable Deployment (v1.0)
    │
    └─── 10% ────► Canary Deployment (v1.1)
                        │
                        ▼
                    Monitor Metrics
                        │
                        ├─── Success? ────► Increase to 25%
                        │
                        └─── Failure? ────► Rollback to 0%
```

---

## File Structure

### File: `k8s/canary-deployment.yaml`

This file contains **two implementation approaches**:

#### 1. Argo Rollouts (Advanced - Lines 1-78)
- Uses `argoproj.io/v1alpha1` API
- Requires Argo Rollouts controller
- Advanced features: automatic analysis, Istio integration

#### 2. Native Kubernetes (Simple - Lines 79-181)
- Uses standard Kubernetes APIs
- No additional controllers required
- Two deployments + two services

---

## How It Works

### Step-by-Step Process

#### Phase 1: Initial Deployment
```
1. Stable version running (v1.0)
   └─> 3 replicas, 100% traffic

2. Deploy canary version (v1.1)
   └─> 1 replica, 0% traffic initially
```

#### Phase 2: Gradual Rollout
```
Step 1: 10% traffic to canary
   └─> Monitor for 5 minutes
   └─> Check success rate ≥ 95%

Step 2: 25% traffic to canary
   └─> Monitor for 5 minutes
   └─> Check success rate ≥ 95%

Step 3: 50% traffic to canary
   └─> Monitor for 5 minutes
   └─> Check success rate ≥ 95%

Step 4: 75% traffic to canary
   └─> Monitor for 5 minutes
   └─> Check success rate ≥ 95%

Step 5: 100% traffic to canary
   └─> Canary becomes stable
   └─> Old stable version removed
```

#### Phase 3: Rollback (if needed)
```
If success rate < 90%:
   └─> Route all traffic back to stable
   └─> Scale down canary to 0
   └─> Investigate issues
   └─> Fix and redeploy
```

---

## Deployment Strategy

### Configuration from File

```yaml
strategy:
  canary:
    steps:
    - setWeight: 10      # 10% traffic to canary
      pause: {duration: 5m}  # Wait 5 minutes
    - setWeight: 25      # Increase to 25%
      pause: {duration: 5m}
    - setWeight: 50      # Increase to 50%
      pause: {duration: 5m}
    - setWeight: 75      # Increase to 75%
      pause: {duration: 5m}
    - setWeight: 100     # Full rollout
```

### Traffic Distribution Over Time

```
Time:    0m    5m    10m   15m   20m   25m
         │     │     │     │     │     │
Stable:  100%  90%   75%   50%   25%   0%
         │     │     │     │     │     │
Canary:  0%    10%   25%   50%   75%   100%
         │     │     │     │     │     │
         └─────┴─────┴─────┴─────┴─────┘
         Monitor at each step
```

---

## Traffic Routing

### How Traffic is Split

#### Option 1: Service Mesh (Istio) - Advanced
```yaml
trafficRouting:
  istio:
    virtualService:
      name: disease-detector-vs
      routes:
      - primary
```

**How it works:**
- Istio VirtualService controls traffic routing
- Weight-based routing (e.g., 90% stable, 10% canary)
- Advanced features: header-based routing, A/B testing

#### Option 2: Native Kubernetes Services - Simple
```yaml
# Stable Service
apiVersion: v1
kind: Service
metadata:
  name: disease-detector-stable
spec:
  selector:
    app: disease-detector
    version: stable

# Canary Service
apiVersion: v1
kind: Service
metadata:
  name: disease-detector-canary
spec:
  selector:
    app: disease-detector
    version: canary
```

**How it works:**
- Two separate services
- Load balancer/ingress routes traffic based on weights
- Simpler but less flexible than service mesh

---

## Monitoring & Rollback

### Automatic Analysis

```yaml
analysis:
  templates:
  - templateName: success-rate
  args:
  - name: service-name
    value: disease-detector-canary
  startingStep: 2
  interval: 30s
  successCondition: result[0].value >= 0.95  # 95% success rate
  failureCondition: result[0].value < 0.90   # Rollback if < 90%
  failureLimit: 2  # Allow 2 failures before rollback
```

### Metrics Monitored

1. **Success Rate**
   - Percentage of successful requests
   - Threshold: ≥ 95% to continue, < 90% to rollback

2. **Error Rate**
   - Percentage of failed requests
   - Monitored continuously

3. **Response Time**
   - Average response time
   - Compared to stable version

4. **Resource Usage**
   - CPU and memory consumption
   - Check for resource leaks

### Rollback Triggers

**Automatic rollback occurs when:**
- Success rate drops below 90%
- Error rate exceeds threshold
- Response time increases significantly
- Resource usage spikes
- Health checks fail

**Manual rollback:**
```bash
# Scale down canary
kubectl scale deployment disease-detector-canary --replicas=0

# Or promote stable
kubectl set image deployment/disease-detector-stable \
  disease-detector=disease-detector:stable
```

---

## Implementation Details

### File Breakdown: `k8s/canary-deployment.yaml`

#### Part 1: Argo Rollouts (Lines 1-78)

**What it is:**
- Advanced canary deployment using Argo Rollouts
- Requires Argo Rollouts controller installed

**Key Components:**
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Rollout
metadata:
  name: disease-detector-rollout
spec:
  replicas: 4
  strategy:
    canary:
      steps: [...]
      canaryService: disease-detector-canary
      stableService: disease-detector-stable
      trafficRouting:
        istio: {...}
      analysis: {...}
```

**Features:**
- Automatic traffic splitting
- Built-in analysis templates
- Istio integration
- Automatic rollback

**Requirements:**
- Argo Rollouts controller
- Istio (for traffic routing)
- Prometheus (for metrics)

#### Part 2: Native Kubernetes (Lines 79-181)

**What it is:**
- Simple canary using standard Kubernetes
- No additional controllers needed

**Key Components:**

1. **Stable Deployment** (Lines 81-116)
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: disease-detector-stable
spec:
  replicas: 3
  selector:
    matchLabels:
      version: stable
  template:
    metadata:
      labels:
        version: stable
    spec:
      containers:
      - image: disease-detector:stable
```

2. **Canary Deployment** (Lines 118-153)
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: disease-detector-canary
spec:
  replicas: 1  # Start with 1 pod
  selector:
    matchLabels:
      version: canary
  template:
    metadata:
      labels:
        version: canary
    spec:
      containers:
      - image: disease-detector:latest  # New version
```

3. **Stable Service** (Lines 170-181)
```yaml
apiVersion: v1
kind: Service
metadata:
  name: disease-detector-stable
spec:
  selector:
    app: disease-detector
    version: stable
```

4. **Canary Service** (Lines 155-168)
```yaml
apiVersion: v1
kind: Service
metadata:
  name: disease-detector-canary
spec:
  selector:
    app: disease-detector
    version: canary
```

### Label-Based Routing

**Key Labels:**
- `app: disease-detector` - Common label for both versions
- `version: stable` - Identifies stable version
- `version: canary` - Identifies canary version

**How Services Route:**
- Stable service selects pods with `version: stable`
- Canary service selects pods with `version: canary`
- Load balancer routes traffic between services

---

## Usage Examples

### Deploy Canary Version

```bash
# 1. Deploy canary deployment
kubectl apply -f k8s/canary-deployment.yaml

# 2. Check status
kubectl get deployments -n disease-detector
kubectl get pods -n disease-detector -l version=canary

# 3. Monitor canary pods
kubectl logs -f -n disease-detector -l version=canary
```

### Monitor Canary Traffic

```bash
# Check pod status
kubectl get pods -n disease-detector

# Check service endpoints
kubectl get endpoints -n disease-detector

# Monitor metrics (if Prometheus available)
kubectl port-forward -n disease-detector svc/prometheus 9090:9090
# Then open http://localhost:9090
```

### Promote Canary to Stable

```bash
# Option 1: Update stable deployment image
kubectl set image deployment/disease-detector-stable \
  disease-detector=disease-detector:latest

# Option 2: Scale up stable, scale down canary
kubectl scale deployment/disease-detector-stable --replicas=3
kubectl scale deployment/disease-detector-canary --replicas=0
```

### Rollback Canary

```bash
# Scale down canary immediately
kubectl scale deployment/disease-detector-canary --replicas=0

# Or delete canary deployment
kubectl delete deployment/disease-detector-canary -n disease-detector
```

### Check Traffic Distribution

```bash
# View service selectors
kubectl get svc -n disease-detector -o wide

# Check which pods are receiving traffic
kubectl get pods -n disease-detector --show-labels

# Monitor requests (if using Istio)
kubectl get virtualservice -n disease-detector
```

---

## Comparison: Canary vs Other Strategies

| Strategy | Risk | Downtime | Rollback Speed | Complexity |
|----------|------|----------|----------------|------------|
| **Canary** | Low | Zero | Fast | Medium |
| **Blue-Green** | Medium | Zero | Instant | Medium |
| **Rolling Update** | Medium | Minimal | Slow | Low |
| **Recreate** | High | Yes | N/A | Low |

### Canary vs Blue-Green

**Canary:**
- Gradual traffic shift
- Both versions run simultaneously
- Lower resource usage
- Better for testing

**Blue-Green:**
- Instant switch (100% traffic)
- Two complete environments
- Higher resource usage
- Better for quick rollback

---

## Summary

### Key Points

1. **Canary Deployment** = Gradual rollout strategy
2. **Not the same as Live Patching** (different concepts)
3. **Zero-downtime** deployments
4. **Automatic rollback** on failure
5. **Production testing** with real traffic

### When to Use

✅ **Use Canary when:**
- Deploying new features
- Updating application code
- Testing ML models
- Want gradual rollout
- Need production validation

❌ **Don't use Canary when:**
- Emergency hot-fixes (use live patching)
- Simple bug fixes (use rolling update)
- Infrastructure-only changes
- Very small applications

### File Location

- **File**: `k8s/canary-deployment.yaml`
- **Contains**: Two implementation approaches
  - Argo Rollouts (advanced)
  - Native Kubernetes (simple)

### Current Status

⚠️ **Note**: The canary deployment file exists but may not be actively used in the current pipeline. It's available as an advanced deployment option.

To enable canary deployments, you would need to:
1. Choose implementation (Argo Rollouts or Native)
2. Configure traffic routing (Istio or Load Balancer)
3. Set up monitoring (Prometheus)
4. Integrate into Jenkins pipeline

---

**Canary deployment is a powerful strategy for safe, gradual rollouts, but it's different from live patching - it's about running two versions simultaneously and gradually shifting traffic, not patching code in memory.**


