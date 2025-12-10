# Ansible Playbook for Kubernetes Deployment

## Overview

This Ansible playbook (`playbook.yaml`) automates the deployment of the Disease Detector application to Kubernetes.

## Flow

### 1. Ensure kubectl is available
- Checks if `kubectl` is installed
- Displays kubectl version
- Fails if kubectl is not found

### 2. Configure Kubernetes cluster access
- Configures access using kubeconfig credentials
- Checks for kubeconfig in:
  - `$HOME/.kube/config` (default)
  - `/etc/kubernetes/admin.conf` (alternative)
- Verifies cluster connection
- Displays cluster information

### 3. Apply Kubernetes deployment yaml files
- Applies namespace
- Applies PVC (PersistentVolumeClaim)
- Applies ConfigMaps
- Applies Services (backend and frontend)
- Applies HPA (HorizontalPodAutoscaler)
- Updates deployment images with new tags
- Applies deployments if they don't exist

### 4. Verify Kubernetes deployments
- Runs `kubectl get deployments` to check deployments
- **Flags error if list is empty** (no deployments found)
- Prints out all deployments
- Displays deployment readiness status

## Usage

### From Jenkins Pipeline (Automated)
```groovy
ansible-playbook -i inventory.yml playbook.yaml \
    -e "docker_image_backend=..." \
    -e "docker_image_frontend=..." \
    -e "kubernetes_namespace=..."
```

### Manual Execution
```bash
cd ansible
ansible-playbook -i inventory.yml playbook.yaml \
    -e "docker_image_backend=varshayamsani/disease-detector-backend:latest" \
    -e "docker_image_frontend=varshayamsani/disease-detector-frontend:latest" \
    -e "kubernetes_namespace=disease-detector"
```

## Verification Steps

The playbook performs these verification steps:

1. **kubectl availability check**
2. **Cluster connection verification**
3. **Deployment verification**:
   - Gets all deployments: `kubectl get deployments`
   - **Fails if empty** (flags error)
   - Prints deployment details
   - Shows readiness status

## Error Handling

- If kubectl is not found → Playbook fails with error message
- If cluster is not accessible → Playbook fails
- **If deployments list is empty → Playbook fails and flags error**
- All errors are clearly displayed

## Output

The playbook provides:
- kubectl version information
- Cluster information
- Deployment status table
- Deployment readiness (replicas ready/total)
- JSON output of deployments

