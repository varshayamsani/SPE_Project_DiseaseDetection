# Complete CI/CD Pipeline Setup Guide

This guide walks you through setting up the complete CI/CD pipeline for the Disease Detector project, step by step.

## 📋 Prerequisites Checklist

Before starting, ensure you have:
- [ ] GitHub account
- [ ] Docker Hub account
- [ ] Jenkins installed (or access to Jenkins server)
- [ ] Kubernetes cluster (Minikube for local, or cloud provider)
- [ ] Basic command-line knowledge

---

## Step 1: GitHub Repository Setup

### 1.1 Create GitHub Repository

1. **Go to GitHub**: https://github.com
2. **Click "New"** (or go to https://github.com/new)
3. **Repository Details**:
   - Repository name: `disease-detector`
   - Description: "AI Disease Detection System with DevOps Pipeline"
   - Visibility: Public or Private (your choice)
   - **DO NOT** initialize with README (we already have files)
4. **Click "Create repository"**

### 1.2 Push Your Code to GitHub

```bash
# Navigate to your project directory
cd /Users/varshayamsani/disease-detector

# Initialize git if not already done
git init

# Add all files
git add .

# Commit
git commit -m "Initial commit: Disease Detector with DevOps setup"

# Add remote (replace YOUR_USERNAME with your GitHub username)
git remote add origin https://github.com/YOUR_USERNAME/disease-detector.git

# Push to GitHub
git branch -M main
git push -u origin main
```

### 1.3 Verify Files Are on GitHub

- Go to your repository: `https://github.com/YOUR_USERNAME/disease-detector`
- Verify these files exist:
  - ✅ `Jenkinsfile`
  - ✅ `Dockerfile`
  - ✅ `docker-compose.yml`
  - ✅ `app.py`
  - ✅ `k8s/` directory with all manifests

---

## Step 2: Docker Hub Setup

### 2.1 Create Docker Hub Account

1. **Go to Docker Hub**: https://hub.docker.com
2. **Sign up** for a free account (if you don't have one)
3. **Verify your email**

### 2.2 Create Docker Hub Repository

1. **Login to Docker Hub**
2. **Click "Create Repository"**
3. **Repository Details**:
   - Name: `disease-detector`
   - Visibility: Public (or Private)
   - Description: "AI Disease Detection Application"
4. **Click "Create"**

### 2.3 Note Your Docker Hub Credentials

- **Username**: Your Docker Hub username
- **Repository**: `YOUR_USERNAME/disease-detector`

You'll need these for Jenkins configuration.

---

## Step 3: Jenkins Installation and Setup

### 3.1 Install Jenkins

#### Option A: Local Installation (macOS/Linux)

```bash
# macOS (using Homebrew)
brew install jenkins-lts

# Start Jenkins
brew services start jenkins-lts

# Or run directly
jenkins-lts
```

#### Option B: Docker Installation (Recommended)

```bash
# Run Jenkins in Docker
docker run -d \
  --name jenkins \
  -p 8080:8080 \
  -p 50000:50000 \
  -v jenkins_home:/var/jenkins_home \
  jenkins/jenkins:lts

# Get initial admin password
docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword
```

#### Option C: Cloud/VM Installation

Follow Jenkins installation guide for your OS:
- Ubuntu: https://www.jenkins.io/doc/book/installing/linux/#debianubuntu
- Windows: https://www.jenkins.io/doc/book/installing/windows/

### 3.2 Initial Jenkins Setup

1. **Open Jenkins**: http://localhost:8080
2. **Unlock Jenkins**:
   - Get initial admin password:
     ```bash
     # Docker
     docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword
     
     # Local installation
     sudo cat /var/lib/jenkins/secrets/initialAdminPassword
     ```
   - Paste password and click "Continue"
3. **Install Suggested Plugins**: Click "Install suggested plugins"
4. **Create Admin User**:
   - Username: `admin` (or your choice)
   - Password: Create a strong password
   - Full name: Your name
   - Email: Your email
5. **Instance Configuration**: Use default URL `http://localhost:8080/`
6. **Click "Save and Finish"**

### 3.3 Install Required Jenkins Plugins

1. **Go to**: Manage Jenkins → Manage Plugins
2. **Click "Available"** tab
3. **Search and install** these plugins:
   - ✅ **GitHub Integration**
   - ✅ **Docker Pipeline**
   - ✅ **Docker**
   - ✅ **Kubernetes CLI**
   - ✅ **Pipeline**
   - ✅ **GitHub**
   - ✅ **GitHub Branch Source**
   - ✅ **Credentials Binding**
   - ✅ **Ansible**
4. **Click "Install without restart"** (or restart if prompted)
5. **Wait for installation** to complete

---

## Step 4: Configure Jenkins Credentials

### 4.1 Add Docker Hub Credentials

1. **Go to**: Manage Jenkins → Manage Credentials
2. **Click "System"** → **"Global credentials"**
3. **Click "Add Credentials"**
4. **Fill in**:
   - **Kind**: Username with password
   - **Scope**: Global
   - **Username**: Your Docker Hub username
   - **Password**: Your Docker Hub password (or access token)
   - **ID**: `docker-hub-credentials` (IMPORTANT: Must match Jenkinsfile)
   - **Description**: "Docker Hub credentials"
5. **Click "OK"**

### 4.2 Add GitHub Credentials (Optional, for private repos)

1. **Create GitHub Personal Access Token**:
   - Go to: https://github.com/settings/tokens
   - Click "Generate new token" → "Generate new token (classic)"
   - Name: `Jenkins CI/CD`
   - Scopes: Select `repo` (full control)
   - Click "Generate token"
   - **Copy the token** (you won't see it again!)

2. **Add to Jenkins**:
   - Go to: Manage Jenkins → Manage Credentials
   - Click "Add Credentials"
   - **Kind**: Secret text
   - **Secret**: Paste your GitHub token
   - **ID**: `github-token`
   - **Description**: "GitHub Personal Access Token"
   - Click "OK"

### 4.3 Configure Kubernetes Credentials (if using K8s)

```bash
# If using Minikube
kubectl config view --minify --flatten > k8s-config.txt

# Add this as a secret file credential in Jenkins
# Or configure Jenkins to use kubectl from PATH
```

---

## Step 5: Configure GitHub Webhook

### 5.1 Enable GitHub Webhook in Jenkins

1. **Go to**: Manage Jenkins → Configure System
2. **Scroll to "GitHub"** section
3. **Click "Add GitHub Server"**
4. **Configuration**:
   - **Name**: `GitHub`
   - **API URL**: `https://api.github.com`
   - **Credentials**: Select your GitHub token (or "None" for public repos)
   - ✅ **Manage hooks**: Check this
5. **Click "Save"**

### 5.2 Add Webhook to GitHub Repository

1. **Go to your GitHub repository**: `https://github.com/YOUR_USERNAME/disease-detector`
2. **Click "Settings"** tab
3. **Click "Webhooks"** in left sidebar
4. **Click "Add webhook"**
5. **Webhook Configuration**:
   - **Payload URL**: `http://YOUR_JENKINS_IP:8080/github-webhook/`
     - If Jenkins is local: `http://localhost:8080/github-webhook/`
     - If Jenkins is on server: `http://YOUR_SERVER_IP:8080/github-webhook/`
   - **Content type**: `application/json`
   - **Which events**: Select "Just the push event"
   - ✅ **Active**: Checked
6. **Click "Add webhook"**
7. **Verify**: You should see a green checkmark ✅

**Note**: If Jenkins is behind a firewall, use a service like:
- **ngrok**: `ngrok http 8080` (for testing)
- **GitHub Actions** (alternative approach)

---

## Step 6: Create Jenkins Pipeline

### 6.1 Create New Pipeline Job

1. **Go to Jenkins Dashboard**
2. **Click "New Item"**
3. **Item Name**: `disease-detector-pipeline`
4. **Type**: Select **"Pipeline"**
5. **Click "OK"**

### 6.2 Configure Pipeline

1. **General Settings**:
   - ✅ **GitHub project**: Check this
   - **Project url**: `https://github.com/YOUR_USERNAME/disease-detector`

2. **Pipeline Configuration**:
   - **Definition**: Pipeline script from SCM
   - **SCM**: Git
   - **Repository URL**: `https://github.com/YOUR_USERNAME/disease-detector.git`
   - **Credentials**: None (for public repo) or select GitHub credentials
   - **Branches to build**: `*/main` (or `*/master`)
   - **Script Path**: `Jenkinsfile` (must match your file name)
   - **Lightweight checkout**: ✅ Checked (optional)

3. **Build Triggers**:
   - ✅ **GitHub hook trigger for GITScm polling**: Check this
   - ✅ **Poll SCM**: Optional (e.g., `H/5 * * * *` for every 5 minutes)

4. **Click "Save"**

---

## Step 7: Update Jenkinsfile with Your Docker Hub Username

### 7.1 Edit Jenkinsfile

```bash
# Open Jenkinsfile
nano Jenkinsfile  # or use your preferred editor
```

### 7.2 Update Docker Image Name

Find this line:
```groovy
DOCKER_IMAGE = 'disease-detector'
```

Change to:
```groovy
DOCKER_IMAGE = 'YOUR_DOCKERHUB_USERNAME/disease-detector'
```

Replace `YOUR_DOCKERHUB_USERNAME` with your actual Docker Hub username.

### 7.3 Commit and Push Changes

```bash
git add Jenkinsfile
git commit -m "Update Docker image name in Jenkinsfile"
git push origin main
```

---

## Step 8: Kubernetes Setup (for Deployment)

### 8.1 Install Kubernetes

#### Option A: Minikube (Local Development)

```bash
# Install Minikube
# macOS
brew install minikube

# Start Minikube
minikube start --cpus=4 --memory=8192

# Verify
kubectl get nodes
```

#### Option B: Cloud Provider

- **Google GKE**: https://cloud.google.com/kubernetes-engine
- **AWS EKS**: https://aws.amazon.com/eks/
- **Azure AKS**: https://azure.microsoft.com/en-us/services/kubernetes-service/

### 8.2 Configure kubectl in Jenkins

**Option 1: Use kubectl from PATH**
- Ensure `kubectl` is installed on Jenkins server
- Jenkins will use system kubectl

**Option 2: Configure in Jenkins**
- Install Kubernetes CLI plugin
- Configure in Manage Jenkins → Configure System

### 8.3 Create Kubernetes Namespace

```bash
# Apply namespace
kubectl apply -f k8s/namespace.yaml

# Verify
kubectl get namespaces
```

---

## Step 9: Test the Pipeline

### 9.1 Trigger Pipeline Manually

1. **Go to Jenkins Dashboard**
2. **Click on** `disease-detector-pipeline`
3. **Click "Build Now"**
4. **Watch the build progress**

### 9.2 Monitor Build Logs

1. **Click on the build number** (#1, #2, etc.)
2. **Click "Console Output"**
3. **Watch for**:
   - ✅ Checkout successful
   - ✅ Build & Test successful
   - ✅ Docker Build successful
   - ✅ Push to Docker Hub successful
   - ✅ Deploy to Kubernetes successful
   - ✅ Health Check successful

### 9.3 Test GitHub Webhook

1. **Make a small change** to your code:
   ```bash
   echo "# Test" >> README.md
   git add README.md
   git commit -m "Test CI/CD pipeline"
   git push origin main
   ```

2. **Go to Jenkins**: The pipeline should automatically trigger
3. **Verify**: New build appears automatically

---

## Step 10: Verify Deployment

### 10.1 Check Docker Hub

1. **Go to**: https://hub.docker.com/r/YOUR_USERNAME/disease-detector
2. **Verify**: New image tags appear after build

### 10.2 Check Kubernetes Deployment

```bash
# Check pods
kubectl get pods -n disease-detector

# Check services
kubectl get svc -n disease-detector

# Check deployment
kubectl get deployment -n disease-detector

# View logs
kubectl logs -f deployment/disease-detector -n disease-detector
```

### 10.3 Access Application

```bash
# Get service URL
kubectl get svc disease-detector-service -n disease-detector

# Port forward (if using NodePort)
kubectl port-forward svc/disease-detector-service 5001:80 -n disease-detector

# Access: http://localhost:5001
```

---

## Step 11: ELK Stack Setup

### 11.1 Start ELK Stack with Docker Compose

```bash
# Start ELK Stack
docker-compose up -d elasticsearch logstash kibana

# Wait for services to start (2-3 minutes)
docker-compose ps

# Check Elasticsearch
curl http://localhost:9200

# Check Kibana (wait 1-2 minutes)
curl http://localhost:5601
```

### 11.2 Configure Kibana

1. **Open Kibana**: http://localhost:5601
2. **First Time Setup**:
   - Click "Explore on my own"
   - Go to: **Stack Management** → **Index Patterns**
   - Click "Create index pattern"
   - Pattern: `disease-detector-logs-*`
   - Time field: `timestamp`
   - Click "Create index pattern"

### 11.3 Verify Log Ingestion

1. **Make a prediction** in your application
2. **Go to Kibana** → **Discover**
3. **Select index pattern**: `disease-detector-logs-*`
4. **Verify**: Logs appear in Kibana

---

## Step 12: Complete Pipeline Verification

### 12.1 End-to-End Test

1. **Make a code change**:
   ```bash
   # Edit app.py - add a comment
   echo "# Updated" >> app.py
   git add app.py
   git commit -m "Test complete CI/CD pipeline"
   git push origin main
   ```

2. **Watch Jenkins**:
   - ✅ Webhook triggers build
   - ✅ Code checked out
   - ✅ Tests run
   - ✅ Docker image built
   - ✅ Image pushed to Docker Hub
   - ✅ Kubernetes deployment updated
   - ✅ Health check passes

3. **Verify Changes**:
   - Refresh application: http://localhost:5001
   - Changes should be visible

4. **Check Logs in Kibana**:
   - New logs appear in Kibana dashboard
   - Application activities visible

---

## Troubleshooting Common Issues

### Issue 1: Webhook Not Triggering

**Solution**:
```bash
# Test webhook manually
curl -X POST http://localhost:8080/github-webhook/ \
  -H "Content-Type: application/json" \
  -d '{"ref":"refs/heads/main"}'

# Check Jenkins logs
docker logs jenkins  # or check Jenkins logs
```

### Issue 2: Docker Build Fails

**Solution**:
```bash
# Test Docker build locally
docker build -t disease-detector:test .

# Check Dockerfile syntax
docker build --no-cache -t disease-detector:test .
```

### Issue 3: Kubernetes Deployment Fails

**Solution**:
```bash
# Check Kubernetes connection
kubectl cluster-info

# Check deployment status
kubectl describe deployment disease-detector -n disease-detector

# Check pod logs
kubectl logs -f deployment/disease-detector -n disease-detector
```

### Issue 4: ELK Stack Not Receiving Logs

**Solution**:
```bash
# Check Logstash
docker logs logstash

# Check Elasticsearch
curl http://localhost:9200/_cat/indices

# Verify log file exists
ls -la logs/disease-detector.log
```

---

## Quick Reference Commands

### Jenkins
```bash
# Start Jenkins (Docker)
docker start jenkins

# View Jenkins logs
docker logs -f jenkins

# Access Jenkins
open http://localhost:8080
```

### Docker
```bash
# Build image
docker build -t YOUR_USERNAME/disease-detector:latest .

# Push to Docker Hub
docker push YOUR_USERNAME/disease-detector:latest

# Test locally
docker run -p 5001:5001 YOUR_USERNAME/disease-detector:latest
```

### Kubernetes
```bash
# Apply all manifests
kubectl apply -f k8s/

# Check status
kubectl get all -n disease-detector

# View logs
kubectl logs -f deployment/disease-detector -n disease-detector

# Port forward
kubectl port-forward svc/disease-detector-service 5001:80 -n disease-detector
```

### Git
```bash
# Push changes (triggers pipeline)
git add .
git commit -m "Your message"
git push origin main
```

---

## Success Checklist

After completing all steps, verify:

- [ ] ✅ Code pushed to GitHub
- [ ] ✅ GitHub webhook configured and working
- [ ] ✅ Jenkins installed and configured
- [ ] ✅ Docker Hub credentials added to Jenkins
- [ ] ✅ Jenkins pipeline created and configured
- [ ] ✅ Pipeline triggers on git push
- [ ] ✅ Docker image builds successfully
- [ ] ✅ Image pushed to Docker Hub
- [ ] ✅ Kubernetes deployment works
- [ ] ✅ Application accessible after deployment
- [ ] ✅ ELK Stack running
- [ ] ✅ Logs visible in Kibana
- [ ] ✅ Changes visible after refresh

---

## Next Steps

Once everything is working:

1. **Monitor Pipeline**: Set up email/Slack notifications
2. **Add More Tests**: Expand test coverage
3. **Production Deployment**: Configure production environment
4. **Backup Strategy**: Set up backups for Jenkins and data
5. **Security Hardening**: Review security best practices

---

**Congratulations!** 🎉 Your complete CI/CD pipeline is now set up and working!

For questions or issues, refer to:
- `DEVOPS_SETUP.md` - Complete DevOps setup guide
- `IMPLEMENTATION_SUMMARY.md` - Implementation overview
- `INNOVATION_FEATURES.md` - Innovative features documentation

