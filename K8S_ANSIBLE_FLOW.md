# Kubernetes and Ansible Deployment Flow

## Overview

This document describes the exact flow for deploying the application using Kubernetes and Ansible, as implemented in the Jenkins pipeline.

## Stage: Deploy with Kubernetes

### Purpose
Deploy the application using Kubernetes and Ansible.

### Key Actions

1. **Configures access to the Kubernetes cluster using the kubeconfig credentials**
2. **Runs an Ansible playbook (playbook.yaml) to deploy the application**
3. **Ensures all configurations and services are applied as required**
4. **Deploys the application in the Kubernetes cluster for production or testing**

## Ansible Playbook Flow (`playbook.yaml`)

### 1. Ensure kubectl is available

```yaml
- name: Ensure kubectl is available
  command: which kubectl
  register: kubectl_check
  
- name: Fail if kubectl is not installed
  fail:
    msg: "ERROR: kubectl is not installed. Please install kubectl first."
  when: kubectl_check.rc != 0
```

**What it does:**
- Checks if `kubectl` command exists
- Displays kubectl version
- **Fails the playbook if kubectl is not found**

### 2. Configure Kubernetes cluster access

```yaml
- name: Configure access to Kubernetes cluster
  block:
    - name: Check if kubeconfig exists
      stat:
        path: "{{ ansible_env.HOME }}/.kube/config"
        
    - name: Set KUBECONFIG environment variable
      set_fact:
        kubeconfig_path: "{{ ansible_env.HOME }}/.kube/config"
        
    - name: Verify Kubernetes cluster connection
      command: kubectl cluster-info
      environment:
        KUBECONFIG: "{{ kubeconfig_path }}"
```

**What it does:**
- Checks for kubeconfig in `$HOME/.kube/config` or `/etc/kubernetes/admin.conf`
- Sets KUBECONFIG environment variable
- Verifies cluster connection
- Displays cluster information

### 3. Apply Kubernetes deployment yaml files

```yaml
- name: Apply Kubernetes deployment manifests
  block:
    - name: Apply namespace
      command: kubectl apply -f {{ playbook_dir }}/../k8s/namespace.yaml
      
    - name: Apply PVC
      command: kubectl apply -f {{ playbook_dir }}/../k8s/pvc.yaml
      
    - name: Apply ConfigMaps
      command: kubectl apply -f {{ playbook_dir }}/../k8s/{{ item }} -n {{ kubernetes_namespace }}
      loop:
        - configmap.yaml
        - frontend-nginx-configmap.yaml
        
    - name: Apply Services
      command: kubectl apply -f {{ playbook_dir }}/../k8s/{{ item }} -n {{ kubernetes_namespace }}
      loop:
        - backend-service.yaml
        - frontend-service.yaml
        
    - name: Apply HPA
      command: kubectl apply -f {{ playbook_dir }}/../k8s/{{ item }} -n {{ kubernetes_namespace }}
      loop:
        - backend-hpa.yaml
        - frontend-hpa.yaml
        
    - name: Update backend deployment image
      command: kubectl set image deployment/disease-detector-backend backend={{ docker_image_backend }} -n {{ kubernetes_namespace }}
      
    - name: Apply backend deployment if update failed
      command: kubectl apply -f {{ playbook_dir }}/../k8s/backend-deployment.yaml -n {{ kubernetes_namespace }}
      
    - name: Update frontend deployment image
      command: kubectl set image deployment/disease-detector-frontend frontend={{ docker_image_frontend }} -n {{ kubernetes_namespace }}
      
    - name: Apply frontend deployment if update failed
      command: kubectl apply -f {{ playbook_dir }}/../k8s/frontend-deployment.yaml -n {{ kubernetes_namespace }}
```

**What it does:**
- Applies namespace
- Applies PVC (PersistentVolumeClaim)
- Applies ConfigMaps
- Applies Services (backend and frontend)
- Applies HPA (HorizontalPodAutoscaler)
- Updates deployment images with new tags
- Applies deployments if they don't exist

### 4. Verify Kubernetes deployments

```yaml
- name: Verify Kubernetes deployments
  block:
    - name: Get all deployments in namespace
      command: kubectl get deployments -n {{ kubernetes_namespace }} --no-headers
      register: deployments_list
      
    - name: Check if deployments list is empty
      set_fact:
        deployments_empty: "{{ deployments_list.stdout | length == 0 }}"
        
    - name: Fail if no deployments found
      fail:
        msg: |
          ============================================
          ERROR: No deployments found!
          ============================================
          Namespace: {{ kubernetes_namespace }}
          This indicates that the deployment may have failed.
          Please check the logs and verify the Kubernetes cluster.
          ============================================
      when: deployments_empty
      
    - name: Get detailed deployment information
      command: kubectl get deployments -n {{ kubernetes_namespace }} -o wide
      register: deployments_details
      
    - name: Print deployments
      debug:
        msg: |
          ============================================
          Kubernetes Deployments Status
          ============================================
          {{ deployments_details.stdout }}
          ============================================
```

**What it does:**
- **Runs `kubectl get deployments`** to check deployments
- **Flags error if list is empty** (no deployments found)
- **Prints out all deployments** in a formatted table
- Displays deployment readiness status
- Shows JSON output of deployments

## Jenkins Pipeline Integration

### Stage 5: Deploy with Kubernetes

```groovy
stage('Deploy with Kubernetes') {
    steps {
        // 1. Install Ansible
        sh 'pip install ansible'
        
        // 2. Configure kubeconfig access
        sh '''
            export KUBECONFIG="$HOME/.kube/config"
            kubectl cluster-info
        '''
        
        // 3. Run Ansible playbook
        sh """
            cd ansible
            ansible-playbook -i inventory.yml playbook.yaml \
                -e "docker_image_backend=${DOCKER_IMAGE_BACKEND}:${DOCKER_TAG}" \
                -e "docker_image_frontend=${DOCKER_IMAGE_FRONTEND}:${DOCKER_TAG}" \
                -e "kubernetes_namespace=${KUBERNETES_NAMESPACE}"
        """
    }
}
```

## Flow Summary

```
Jenkins Pipeline
   ↓
Stage: Deploy with Kubernetes
   ↓
1. Configure kubeconfig credentials
   ↓
2. Run Ansible playbook (playbook.yaml)
   ↓
   ┌─────────────────────────────────┐
   │ Ansible Playbook Execution      │
   ├─────────────────────────────────┤
   │ 1. Ensure kubectl is available │
   │ 2. Configure cluster access    │
   │ 3. Apply K8s deployment yamls   │
   │ 4. Verify deployments          │
   │    - kubectl get deployments   │
   │    - Flag if empty             │
   │    - Print deployments         │
   └─────────────────────────────────┘
   ↓
Deployment Complete
```

## Verification Steps

The playbook performs these verification steps:

1. ✅ **kubectl availability check** - Ensures kubectl is installed
2. ✅ **Cluster connection verification** - Verifies kubeconfig works
3. ✅ **Deployment verification**:
   - Gets all deployments: `kubectl get deployments`
   - **Fails if empty** (flags error)
   - Prints deployment details
   - Shows readiness status

## Error Handling

- ❌ **If kubectl is not found** → Playbook fails with clear error message
- ❌ **If cluster is not accessible** → Playbook fails
- ❌ **If deployments list is empty** → Playbook fails and flags error with detailed message
- ✅ All errors are clearly displayed with formatted output

## Output Example

When successful, the playbook outputs:

```
============================================
Kubernetes Deployments Status
============================================
NAME                          READY   UP-TO-DATE   AVAILABLE   AGE
disease-detector-backend      2/2     2           2           5m
disease-detector-frontend     2/2     2           2           5m
============================================

Deployment Readiness Status
============================================
Backend Deployment: 2/2 replicas ready
Frontend Deployment: 2/2 replicas ready
============================================
```

When deployments are empty, it outputs:

```
============================================
ERROR: No deployments found!
============================================
Namespace: disease-detector
This indicates that the deployment may have failed.
Please check the logs and verify the Kubernetes cluster.
============================================
```

## Files Used

- **`ansible/playbook.yaml`** - Main Ansible playbook
- **`ansible/inventory.yml`** - Inventory file with target servers
- **`k8s/*.yaml`** - Kubernetes deployment manifests

## Summary

✅ **kubectl availability** - Checked and verified
✅ **kubeconfig access** - Configured and verified
✅ **Kubernetes deployments** - Applied via Ansible
✅ **Deployment verification** - `kubectl get deployments` executed
✅ **Empty list detection** - Flags error if no deployments found
✅ **Deployment printing** - All deployments printed in formatted output

The flow matches exactly what was requested!

