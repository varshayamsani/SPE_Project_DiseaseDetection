# Jenkins Pipeline - Separate Frontend/Backend Builds

## ✅ Updated Pipeline Structure

The Jenkins pipeline now properly builds and deploys **separate frontend and backend images**.

## Pipeline Stages

### Stage 1: Checkout
- Checks out code from GitHub

### Stage 2: Build & Test
- Creates virtual environment
- Installs dependencies
- Runs tests

### Stage 3: Docker Build (Parallel)
Builds **both** images simultaneously:

**Backend Image:**
- Uses: `Dockerfile.backend`
- Builds: `varshayamsani/disease-detector-backend:${BUILD_NUMBER}`
- Tags: `varshayamsani/disease-detector-backend:latest`

**Frontend Image:**
- Uses: `Dockerfile.frontend`
- Builds: `varshayamsani/disease-detector-frontend:${BUILD_NUMBER}`
- Tags: `varshayamsani/disease-detector-frontend:latest`

### Stage 4: Push to Docker Hub (Parallel)
Pushes **both** images simultaneously:
- Backend: `varshayamsani/disease-detector-backend:*`
- Frontend: `varshayamsani/disease-detector-frontend:*`

### Stage 5: Deploy to Kubernetes
Deploys **both** services:
- Updates backend deployment with new backend image
- Updates frontend deployment with new frontend image
- Waits for both rollouts to complete

### Stage 6: Health Check
Verifies **both** services:
- Backend health: `http://disease-detector-backend-service:5001/health`
- Frontend health: `http://disease-detector-frontend-service/health`

## Environment Variables

```groovy
DOCKER_IMAGE_BASE = 'varshayamsani/disease-detector'
DOCKER_IMAGE_BACKEND = 'varshayamsani/disease-detector-backend'
DOCKER_IMAGE_FRONTEND = 'varshayamsani/disease-detector-frontend'
DOCKER_TAG = "${BUILD_NUMBER}"
```

## Image Names

- **Backend**: `varshayamsani/disease-detector-backend:latest`
- **Frontend**: `varshayamsani/disease-detector-frontend:latest`

## Dockerfiles Used

1. **Dockerfile.backend** → Backend image
   - Python 3.11
   - Flask API only
   - No templates/static files

2. **Dockerfile.frontend** → Frontend image
   - Nginx Alpine
   - Static files and templates
   - Nginx configuration

## Kubernetes Deployments

### Backend Deployment
- **Name**: `disease-detector-backend`
- **Container**: `backend`
- **Image**: Updated by Jenkins to `${DOCKER_IMAGE_BACKEND}:${DOCKER_TAG}`

### Frontend Deployment
- **Name**: `disease-detector-frontend`
- **Container**: `frontend`
- **Image**: Updated by Jenkins to `${DOCKER_IMAGE_FRONTEND}:${DOCKER_TAG}`

## Benefits

1. ✅ **Separate Builds**: Each service builds independently
2. ✅ **Parallel Execution**: Both images build/push simultaneously (faster)
3. ✅ **Independent Updates**: Can update frontend or backend separately
4. ✅ **Proper Separation**: True microservices architecture
5. ✅ **Optimized Images**: Smaller, focused images

## Verification

After pipeline runs, verify:

```bash
# Check images in Docker Hub
docker pull varshayamsani/disease-detector-backend:latest
docker pull varshayamsani/disease-detector-frontend:latest

# Check Kubernetes deployments
kubectl get deployment -n disease-detector
kubectl describe deployment disease-detector-backend -n disease-detector
kubectl describe deployment disease-detector-frontend -n disease-detector

# Check images used
kubectl get deployment disease-detector-backend -n disease-detector -o jsonpath='{.spec.template.spec.containers[0].image}'
kubectl get deployment disease-detector-frontend -n disease-detector -o jsonpath='{.spec.template.spec.containers[0].image}'
```

## Pipeline Flow Diagram

```
Git Push
   ↓
GitHub Webhook
   ↓
Jenkins Pipeline
   ↓
┌─────────────────────────────────┐
│  Stage 1: Checkout              │
└─────────────────────────────────┘
   ↓
┌─────────────────────────────────┐
│  Stage 2: Build & Test          │
└─────────────────────────────────┘
   ↓
┌─────────────────────────────────┐
│  Stage 3: Docker Build          │
│  ┌──────────┐  ┌──────────┐    │
│  │ Backend  │  │ Frontend │    │
│  │  Build   │  │  Build   │    │
│  └──────────┘  └──────────┘    │
└─────────────────────────────────┘
   ↓
┌─────────────────────────────────┐
│  Stage 4: Push to Docker Hub    │
│  ┌──────────┐  ┌──────────┐    │
│  │ Backend  │  │ Frontend │    │
│  │  Push    │  │  Push    │    │
│  └──────────┘  └──────────┘    │
└─────────────────────────────────┘
   ↓
┌─────────────────────────────────┐
│  Stage 5: Deploy to K8s         │
│  ┌──────────┐  ┌──────────┐    │
│  │ Backend  │  │ Frontend │    │
│  │ Deploy   │  │ Deploy   │    │
│  └──────────┘  └──────────┘    │
└─────────────────────────────────┘
   ↓
┌─────────────────────────────────┐
│  Stage 6: Health Check          │
│  ┌──────────┐  ┌──────────┐    │
│  │ Backend  │  │ Frontend │    │
│  │  Check   │  │  Check   │    │
│  └──────────┘  └──────────┘    │
└─────────────────────────────────┘
   ↓
✅ Success!
```

## Summary

✅ **Separate Dockerfiles**: `Dockerfile.backend` and `Dockerfile.frontend`
✅ **Separate Images**: Two distinct images built and pushed
✅ **Parallel Builds**: Faster pipeline execution
✅ **Independent Deployments**: Each service deployed separately
✅ **Proper Architecture**: True microservices separation

The pipeline is now correctly configured for separate frontend and backend services!

