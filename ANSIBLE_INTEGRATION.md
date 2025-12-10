# Ansible Integration in CI/CD Pipeline

## Overview

Ansible is now integrated into the Jenkins CI/CD pipeline for **Configuration Management** and **Infrastructure Deployment**.

## How It Works

### Pipeline Flow

```
Git Push → GitHub Webhook → Jenkins Pipeline
   ↓
Checkout Code
   ↓
Build & Test
   ↓
Build Docker Images (Backend + Frontend)
   ↓
Push to Docker Hub
   ↓
**Deploy with Ansible** ← Configuration Management
   ↓
Health Check
```

## Ansible Stage in Jenkinsfile

### Stage 5: Deploy with Ansible

```groovy
stage('Deploy with Ansible') {
    steps {
        // Install Ansible if needed
        // Run playbook with inventory
        ansible-playbook -i inventory.yml playbook.yml \
            -e "docker_image_backend=..." \
            -e "docker_image_frontend=..." \
            -e "kubernetes_namespace=..."
    }
}
```

## Ansible Components Used

### 1. Inventory File (`ansible/inventory.yml`)
- Defines target servers (dev/prod)
- Configures connection details
- Used by Jenkins pipeline

### 2. Playbook (`ansible/playbook.yml`)
- Main orchestration file
- Uses modular roles
- Passes variables from Jenkins

### 3. Roles (Modular Design)
- **common**: System setup
- **docker**: Docker installation
- **k8s**: Kubernetes deployment ← **Used in pipeline**
- **elk**: ELK Stack setup

### 4. Ansible Config (`ansible/ansible.cfg`)
- Configuration settings
- Inventory path
- Vault password file

## What Ansible Does in Pipeline

1. **Verifies kubectl** is installed
2. **Checks Kubernetes** cluster connection
3. **Creates namespace** if needed
4. **Applies all K8s manifests**:
   - Namespace
   - PVC
   - ConfigMaps
   - Services
   - HPA
   - Deployments
5. **Updates deployment images** with new tags
6. **Waits for rollouts** to complete
7. **Reports status** of deployments

## Variables Passed from Jenkins

```groovy
-e "docker_image_backend=${DOCKER_IMAGE_BACKEND}:${DOCKER_TAG}"
-e "docker_image_frontend=${DOCKER_IMAGE_FRONTEND}:${DOCKER_TAG}"
-e "kubernetes_namespace=${KUBERNETES_NAMESPACE}"
```

## Inventory Configuration

### For Local Development
```yaml
dev:
  hosts:
    localhost:
      ansible_connection: local
```

### For Production
```yaml
prod:
  hosts:
    production-server:
      ansible_host: your-production-ip
      ansible_user: ubuntu
      ansible_ssh_private_key_file: ~/.ssh/id_rsa
```

## Running Ansible Manually

### From Jenkins (Automated)
- Runs automatically in pipeline
- Uses inventory.yml
- Passes variables from Jenkins

### From Command Line (Manual)
```bash
cd ansible

# Deploy to dev environment
ansible-playbook -i inventory.yml playbook.yml \
    -e "docker_image_backend=varshayamsani/disease-detector-backend:latest" \
    -e "docker_image_frontend=varshayamsani/disease-detector-frontend:latest" \
    --tags k8s

# Deploy to prod environment
ansible-playbook -i inventory.yml playbook.yml \
    -e "docker_image_backend=varshayamsani/disease-detector-backend:1.0" \
    -e "docker_image_frontend=varshayamsani/disease-detector-frontend:1.0" \
    --limit prod \
    --tags k8s
```

## Benefits of Using Ansible

1. **Infrastructure as Code**: K8s resources defined in Ansible
2. **Idempotent**: Safe to run multiple times
3. **Modular**: Roles can be reused
4. **Environment Management**: Different configs for dev/prod
5. **Audit Trail**: Ansible logs all changes
6. **Rollback**: Can revert changes easily
7. **Compliance**: Meets project requirement for Ansible

## Ansible Roles Used

### Role: k8s (Kubernetes Deployment)
- **Location**: `ansible/roles/k8s/tasks/main.yml`
- **Purpose**: Deploy application to Kubernetes
- **Tasks**:
  - Verify kubectl
  - Create namespace
  - Apply manifests
  - Update images
  - Wait for rollouts
  - Report status

### Role: common (System Setup)
- **Location**: `ansible/roles/common/tasks/main.yml`
- **Purpose**: System prerequisites
- **Tasks**: Install packages, create directories

### Role: docker (Docker Installation)
- **Location**: `ansible/roles/docker/tasks/main.yml`
- **Purpose**: Install Docker
- **Tasks**: Install Docker, Docker Compose

### Role: elk (ELK Stack)
- **Location**: `ansible/roles/elk/tasks/main.yml`
- **Purpose**: Deploy ELK Stack
- **Tasks**: Start ELK services, configure

## Pipeline Integration

### Jenkinsfile Stage
```groovy
stage('Deploy with Ansible') {
    steps {
        sh """
            cd ansible
            ansible-playbook -i inventory.yml playbook.yml \
                -e "docker_image_backend=..." \
                -e "docker_image_frontend=..." \
                --tags k8s
        """
    }
}
```

### What Happens
1. Jenkins runs Ansible playbook
2. Ansible reads inventory.yml
3. Ansible executes k8s role
4. Role deploys to Kubernetes
5. Pipeline continues to health check

## Troubleshooting

### Ansible Not Found
```bash
# Install in Jenkins
pip install ansible
```

### Kubernetes Collection Missing
```bash
ansible-galaxy collection install kubernetes.core
```

### Inventory File Not Found
- Ensure `ansible/inventory.yml` exists
- Check path in Jenkinsfile

### kubectl Not Available
- Ensure kubectl is in PATH
- Or configure in Ansible role

## Summary

✅ **Ansible integrated** into Jenkins pipeline
✅ **Uses inventory.yml** for target servers
✅ **Uses playbook.yml** with modular roles
✅ **Deploys Kubernetes** resources
✅ **Updates images** with new tags
✅ **Meets project requirements** for Configuration Management

The pipeline now uses Ansible for all Kubernetes deployments, meeting the project requirement for Configuration Management!

