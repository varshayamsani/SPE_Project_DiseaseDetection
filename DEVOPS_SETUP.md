# DevOps Setup Guide for Disease Detector Application

This document provides a comprehensive, step-by-step guide to set up the complete DevOps infrastructure for the Disease Detector application.

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Architecture Overview](#architecture-overview)
3. [Step-by-Step Setup](#step-by-step-setup)
4. [CI/CD Pipeline](#cicd-pipeline)
5. [Monitoring and Logging](#monitoring-and-logging)
6. [Scaling and High Availability](#scaling-and-high-availability)
7. [Security](#security)
8. [Troubleshooting](#troubleshooting)

---

## Prerequisites

### Required Software
- **Git** (Version 2.30+)
- **Docker** (Version 20.10+)
- **Docker Compose** (Version 2.0+)
- **Kubernetes** (Version 1.25+) - Minikube or cloud K8s cluster
- **Jenkins** (Version 2.400+)
- **Ansible** (Version 2.14+)
- **Python** (Version 3.11+)
- **kubectl** (Kubernetes CLI)
- **Vault** (HashiCorp Vault 1.14+)

### System Requirements
- **CPU**: 4+ cores
- **RAM**: 8GB+ (16GB recommended for full stack)
- **Storage**: 50GB+ free space
- **OS**: Linux (Ubuntu 20.04+ recommended) or macOS

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    GitHub Repository                         │
│              (Version Control with Git)                      │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       │ (Webhook Trigger)
                       ▼
┌─────────────────────────────────────────────────────────────┐
│                    Jenkins CI/CD                             │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐  │
│  │  Build   │→ │   Test   │→ │  Docker  │→ │  Deploy  │  │
│  └──────────┘  └──────────┘  └──────────┘  └──────────┘  │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│                  Docker Hub Registry                         │
│              (Container Image Storage)                       │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│              Kubernetes Cluster (K8s)                        │
│  ┌──────────────────────────────────────────────────────┐  │
│  │  Disease Detector Deployment (HPA Enabled)            │  │
│  │  ┌────────┐  ┌────────┐  ┌────────┐  ┌────────┐     │  │
│  │  │ Pod 1  │  │ Pod 2  │  │ Pod 3  │  │ Pod N  │     │  │
│  │  └────────┘  └────────┘  └────────┘  └────────┘     │  │
│  └──────────────────────────────────────────────────────┘  │
│  ┌──────────────────────────────────────────────────────┐  │
│  │  ELK Stack (Elasticsearch, Logstash, Kibana)         │  │
│  └──────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│              HashiCorp Vault                                 │
│         (Secure Credential Storage)                         │
└─────────────────────────────────────────────────────────────┘
```

---

## Step-by-Step Setup

### Step 1: Version Control Setup (Git & GitHub)

1. **Initialize Git Repository** (if not already done):
   ```bash
   cd /path/to/disease-detector
   git init
   git add .
   git commit -m "Initial commit with DevOps setup"
   ```

2. **Create GitHub Repository**:
   - Go to GitHub and create a new repository
   - Add remote and push:
   ```bash
   git remote add origin https://github.com/yourusername/disease-detector.git
   git branch -M main
   git push -u origin main
   ```

3. **Configure GitHub Webhook** (for Jenkins):
   - Go to repository Settings → Webhooks
   - Add webhook: `http://your-jenkins-url/github-webhook/`
   - Content type: `application/json`
   - Events: Push, Pull Request

---

### Step 2: Docker Setup

1. **Build Docker Image Locally**:
   ```bash
   docker build -t disease-detector:latest .
   ```

2. **Test Docker Image**:
   ```bash
   docker run -d -p 5001:5001 --name disease-detector disease-detector:latest
   curl http://localhost:5001/health
   ```

3. **Docker Compose Setup** (includes ELK Stack):
   ```bash
   docker-compose up -d
   ```

4. **Verify All Services**:
   ```bash
   docker-compose ps
   # Check:
   # - disease-detector-app (port 5001)
   # - elasticsearch (port 9200)
   # - logstash (port 5044)
   # - kibana (port 5601)
   ```

---

### Step 3: Jenkins CI/CD Setup

1. **Install Jenkins**:
   ```bash
   # On Ubuntu/Debian
   wget -q -O - https://pkg.jenkins.io/debian/jenkins.io-2023.key | sudo apt-key add -
   sudo sh -c 'echo deb http://pkg.jenkins.io/debian-stable binary/ > /etc/apt/sources.list.d/jenkins.list'
   sudo apt-get update
   sudo apt-get install jenkins
   ```

2. **Start Jenkins**:
   ```bash
   sudo systemctl start jenkins
   sudo systemctl enable jenkins
   ```

3. **Access Jenkins**:
   - Open browser: `http://localhost:8080`
   - Get initial admin password: `sudo cat /var/lib/jenkins/secrets/initialAdminPassword`
   - Install suggested plugins

4. **Configure Jenkins**:
   - Install required plugins:
     - GitHub Integration
     - Docker Pipeline
     - Kubernetes CLI
     - Ansible
     - Pipeline

5. **Create Jenkins Credentials**:
   - Go to: Manage Jenkins → Credentials → System → Global
   - Add Docker Hub credentials:
     - Kind: Username with password
     - ID: `docker-hub-credentials`
     - Username: Your Docker Hub username
     - Password: Your Docker Hub password/token

6. **Create Jenkins Pipeline**:
   - New Item → Pipeline
   - Name: `disease-detector-pipeline`
   - Pipeline definition: Pipeline script from SCM
   - SCM: Git
   - Repository URL: Your GitHub repository URL
   - Script Path: `Jenkinsfile`

7. **Configure GitHub Webhook in Jenkins**:
   - Manage Jenkins → Configure System
   - GitHub: Add GitHub Server
   - API URL: `https://api.github.com`
   - Credentials: Add GitHub personal access token

---

### Step 4: Ansible Configuration Management

1. **Install Ansible**:
   ```bash
   pip install ansible
   ```

2. **Configure Inventory**:
   - Edit `ansible/inventory.yml` with your server details
   - For local testing:
     ```yaml
     all:
       hosts:
         localhost:
           ansible_connection: local
     ```

3. **Set Up Vault Password** (for encrypted variables):
   ```bash
   echo "your-vault-password" > ansible/.vault_pass
   chmod 600 ansible/.vault_pass
   ```

4. **Run Ansible Playbook**:
   ```bash
   cd ansible
   ansible-playbook -i inventory.yml playbook.yml
   ```

5. **Run Specific Roles**:
   ```bash
   # Only Docker
   ansible-playbook -i inventory.yml playbook.yml --tags docker
   
   # Only Kubernetes
   ansible-playbook -i inventory.yml playbook.yml --tags k8s
   
   # Only ELK Stack
   ansible-playbook -i inventory.yml playbook.yml --tags elk
   ```

---

### Step 5: Kubernetes Deployment

1. **Set Up Kubernetes Cluster**:
   ```bash
   # Using Minikube (for local development)
   minikube start --cpus=4 --memory=8192
   
   # Or use cloud provider (GKE, EKS, AKS)
   ```

2. **Create Namespace**:
   ```bash
   kubectl apply -f k8s/namespace.yaml
   ```

3. **Create Persistent Volume Claim**:
   ```bash
   kubectl apply -f k8s/pvc.yaml
   ```

4. **Deploy Application**:
   ```bash
   kubectl apply -f k8s/deployment.yaml
   kubectl apply -f k8s/service.yaml
   kubectl apply -f k8s/hpa.yaml
   ```

5. **Verify Deployment**:
   ```bash
   kubectl get pods -n disease-detector
   kubectl get services -n disease-detector
   kubectl get hpa -n disease-detector
   ```

6. **Check Application**:
   ```bash
   # Get service URL
   kubectl get svc -n disease-detector
   # Access application (use NodePort or LoadBalancer IP)
   ```

---

### Step 6: ELK Stack Configuration

1. **Start ELK Stack with Docker Compose**:
   ```bash
   docker-compose up -d elasticsearch logstash kibana
   ```

2. **Wait for Services to be Ready**:
   ```bash
   # Check Elasticsearch
   curl http://localhost:9200
   
   # Check Kibana (wait 1-2 minutes)
   curl http://localhost:5601
   ```

3. **Configure Kibana Index Pattern**:
   - Open Kibana: `http://localhost:5601`
   - Go to: Stack Management → Index Patterns
   - Create pattern: `disease-detector-logs-*`
   - Time field: `timestamp`

4. **Verify Log Ingestion**:
   - Make a prediction request to the application
   - Check Kibana → Discover
   - You should see logs appearing

---

### Step 7: HashiCorp Vault Setup

1. **Install Vault**:
   ```bash
   # Download from https://www.vaultproject.io/downloads
   # Or use package manager
   brew install vault  # macOS
   sudo apt install vault  # Ubuntu
   ```

2. **Start Vault Server**:
   ```bash
   mkdir -p vault/data
   vault server -config=vault-config.hcl
   ```

3. **Initialize Vault**:
   ```bash
   ./vault-setup.sh
   ```

4. **Access Vault UI**:
   - Open: `http://localhost:8200`
   - Login with root token from `vault-credentials.txt`

5. **Retrieve Secrets in Application** (optional integration):
   ```python
   import hvac
   client = hvac.Client(url='http://vault:8200', token=os.getenv('VAULT_TOKEN'))
   secret = client.secrets.kv.v2.read_secret_version(path='disease-detector/app')
   ```

---

## CI/CD Pipeline

### Automated Workflow

When you push code to GitHub:

1. **GitHub Webhook** triggers Jenkins
2. **Jenkins Pipeline** executes:
   - **Checkout**: Gets latest code
   - **Build & Test**: Runs unit tests
   - **Docker Build**: Creates container image
   - **Push**: Uploads to Docker Hub
   - **Deploy**: Updates Kubernetes deployment
   - **Health Check**: Verifies deployment

### Manual Pipeline Trigger

```bash
# Trigger Jenkins build manually
curl -X POST http://jenkins-url/job/disease-detector-pipeline/build \
  --user username:api-token
```

---

## Monitoring and Logging

### Application Logs

1. **View Application Logs**:
   ```bash
   # Docker
   docker logs disease-detector-app
   
   # Kubernetes
   kubectl logs -f deployment/disease-detector -n disease-detector
   ```

2. **Kibana Dashboard**:
   - Access: `http://localhost:5601`
   - Create visualizations for:
     - Request count over time
     - Error rates
     - Prediction accuracy
     - Patient activity

### Health Monitoring

```bash
# Check application health
curl http://localhost:5001/health

# Expected response:
{
  "status": "healthy",
  "models_loaded": 3,
  "ensemble_mode": true
}
```

---

## Scaling and High Availability

### Horizontal Pod Autoscaling (HPA)

The HPA automatically scales pods based on:
- **CPU Usage**: Scales when > 70%
- **Memory Usage**: Scales when > 80%
- **Min Pods**: 2
- **Max Pods**: 10

**Check HPA Status**:
```bash
kubectl get hpa -n disease-detector
kubectl describe hpa disease-detector-hpa -n disease-detector
```

### Manual Scaling

```bash
# Scale manually
kubectl scale deployment/disease-detector --replicas=5 -n disease-detector
```

### Live Patching (Zero Downtime Updates)

Jenkins pipeline automatically performs rolling updates:
```bash
# Kubernetes rolling update
kubectl set image deployment/disease-detector \
  disease-detector=disease-detector:new-tag \
  -n disease-detector

# Monitor rollout
kubectl rollout status deployment/disease-detector -n disease-detector
```

---

## Security

### Vault Integration

1. **Store Secrets in Vault**:
   ```bash
   vault kv put disease-detector/docker \
     username="dockerhub-user" \
     password="dockerhub-token"
   ```

2. **Retrieve in Jenkins**:
   - Use Vault plugin or API calls
   - Never commit secrets to Git

### Best Practices

- ✅ All secrets in Vault
- ✅ Docker images scanned for vulnerabilities
- ✅ Kubernetes network policies
- ✅ TLS/SSL for production
- ✅ Regular security updates

---

## Troubleshooting

### Common Issues

1. **Jenkins Pipeline Fails**:
   ```bash
   # Check Jenkins logs
   sudo tail -f /var/log/jenkins/jenkins.log
   
   # Check pipeline console output in Jenkins UI
   ```

2. **Docker Build Fails**:
   ```bash
   # Check Docker daemon
   docker info
   
   # Clean build
   docker build --no-cache -t disease-detector:latest .
   ```

3. **Kubernetes Pods Not Starting**:
   ```bash
   # Check pod status
   kubectl describe pod <pod-name> -n disease-detector
   
   # Check events
   kubectl get events -n disease-detector
   ```

4. **ELK Stack Not Receiving Logs**:
   ```bash
   # Check Logstash
   docker logs logstash
   
   # Check Elasticsearch
   curl http://localhost:9200/_cat/indices
   ```

5. **Application Not Accessible**:
   ```bash
   # Check service
   kubectl get svc -n disease-detector
   
   # Port forward for testing
   kubectl port-forward svc/disease-detector-service 5001:80 -n disease-detector
   ```

---

## Quick Start Commands

```bash
# Full stack deployment
docker-compose up -d

# Kubernetes deployment
kubectl apply -f k8s/

# Ansible deployment
cd ansible && ansible-playbook -i inventory.yml playbook.yml

# Check everything
docker-compose ps
kubectl get all -n disease-detector
curl http://localhost:5001/health
```

---

## Next Steps

1. ✅ Set up monitoring alerts
2. ✅ Configure backup for database
3. ✅ Set up staging environment
4. ✅ Implement blue-green deployments
5. ✅ Add performance testing

---

## Support

For issues or questions:
- Check logs in Kibana
- Review Jenkins pipeline console
- Check Kubernetes events
- Review application logs

---

**Last Updated**: 2024
**Version**: 1.0


