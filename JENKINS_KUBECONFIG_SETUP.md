# Jenkins Kubernetes Configuration Setup

## Overview

This guide explains how to configure Jenkins to deploy to Kubernetes using kubeconfig credentials and the Ansible playbook.

## Prerequisites

1. **Kubernetes Plugin** installed in Jenkins
2. **Kubeconfig file** available
3. **Jenkins Service Account** created in Kubernetes (optional but recommended)

## Step 1: Create Jenkins Service Account in Kubernetes

Apply the `jenkins-service.yaml` file to create the service account:

```bash
kubectl apply -f k8s/jenkins-service.yaml
```

This creates:
- Service Account: `jenkins-service-account`
- ClusterRole: `jenkins-deployer` (with necessary permissions)
- ClusterRoleBinding: `jenkins-deployer-binding`
- Secret: `jenkins-service-account-token`

## Step 2: Configure Kubeconfig Credential in Jenkins

### Option A: Using Jenkins Kubernetes Plugin

1. Go to **Jenkins Dashboard** → **Manage Jenkins** → **Manage Credentials**
2. Click **Add Credentials**
3. Select **Kubernetes configuration (kubeconfig)**
4. Configure:
   - **ID**: `kubeconfig` (must match the credential ID in Jenkinsfile)
   - **Description**: `Kubernetes cluster kubeconfig`
   - **Kubeconfig**: Select **Enter directly** or **From a file on Jenkins master**
   - **Content**: Paste your kubeconfig content or upload the file
5. Click **OK**

### Option B: Using Service Account Token

If using the Jenkins service account:

```bash
# Get the service account token
kubectl get secret jenkins-service-account-token -n disease-detector -o jsonpath='{.data.token}' | base64 -d

# Get the cluster CA certificate
kubectl get secret jenkins-service-account-token -n disease-detector -o jsonpath='{.data.ca\.crt}'

# Get the cluster server URL
kubectl cluster-info | grep 'Kubernetes control plane'
```

Then create a kubeconfig file:

```yaml
apiVersion: v1
kind: Config
clusters:
- cluster:
    certificate-authority-data: <CA_CERT>
    server: <CLUSTER_URL>
  name: kubernetes-cluster
contexts:
- context:
    cluster: kubernetes-cluster
    user: jenkins-service-account
    namespace: disease-detector
  name: jenkins-context
current-context: jenkins-context
users:
- name: jenkins-service-account
  user:
    token: <SERVICE_ACCOUNT_TOKEN>
```

## Step 3: Jenkinsfile Configuration

The Jenkinsfile uses `withKubeConfig` to configure kubeconfig:

```groovy
withKubeConfig([credentialsId: 'kubeconfig', serverUrl: '']) {
    sh """
        cd ansible
        ansible-playbook -i inventory.yml playbook.yaml \
            -e "kubeconfig_path=\${KUBECONFIG}" \
            -e "docker_image_backend=..." \
            -e "docker_image_frontend=..." \
            -e "kubernetes_namespace=disease-detector"
    """
}
```

### Parameters:

- **credentialsId**: `'kubeconfig'` - Must match the credential ID in Jenkins
- **serverUrl**: `''` - Empty string uses the server from kubeconfig
- **KUBECONFIG**: Automatically set by `withKubeConfig` block

## Step 4: Ansible Playbook

The playbook (`ansible/playbook.yaml`) uses the kubeconfig path:

```yaml
vars:
  kubeconfig_path: "{{ kubeconfig_path | default('') }}"

tasks:
  - name: Apply Kubernetes deployment YAML files
    shell: |
      {% if kubeconfig_path %}
      export KUBECONFIG={{ kubeconfig_path }}
      {% endif %}
      kubectl apply -f ...
```

## Verification

### Test Jenkins Access

1. Run the Jenkins pipeline
2. Check the "Deploy with Kubernetes" stage output
3. Verify:
   - ✅ kubectl version displayed
   - ✅ Kubernetes resources applied
   - ✅ Deployments verified
   - ✅ Deployments printed

### Manual Test

```bash
# Set kubeconfig
export KUBECONFIG=/path/to/kubeconfig

# Test access
kubectl get deployments -n disease-detector

# Run Ansible playbook manually
cd ansible
ansible-playbook -i inventory.yml playbook.yaml \
    -e "kubeconfig_path=$KUBECONFIG" \
    -e "docker_image_backend=varshayamsani/disease-detector-backend:latest" \
    -e "docker_image_frontend=varshayamsani/disease-detector-frontend:latest" \
    -e "kubernetes_namespace=disease-detector"
```

## Troubleshooting

### Error: "No such credential: kubeconfig"

**Solution**: Create the credential in Jenkins with ID `kubeconfig`

### Error: "Unable to connect to the server"

**Solution**: 
- Verify kubeconfig is valid
- Check cluster server URL is accessible
- Verify service account has permissions

### Error: "Forbidden" or "Unauthorized"

**Solution**:
- Apply `jenkins-service.yaml` to create service account
- Verify ClusterRoleBinding is correct
- Check service account token is valid

### Error: "kubectl: command not found"

**Solution**: Install kubectl on Jenkins agent

```bash
# On Jenkins agent
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl
sudo mv kubectl /usr/local/bin/
```

## Files

- **`k8s/jenkins-service.yaml`** - Jenkins service account and RBAC
- **`ansible/playbook.yaml`** - Ansible playbook for deployment
- **`Jenkinsfile`** - CI/CD pipeline with kubeconfig integration

## Summary

✅ **Service Account Created** - `jenkins-service-account` with deploy permissions
✅ **Kubeconfig Credential** - Configured in Jenkins with ID `kubeconfig`
✅ **Jenkinsfile Updated** - Uses `withKubeConfig` for secure access
✅ **Ansible Playbook** - Uses kubeconfig path from Jenkins
✅ **Deployment Flow** - Complete CI/CD pipeline ready

The setup is now complete for Jenkins to deploy to Kubernetes!

