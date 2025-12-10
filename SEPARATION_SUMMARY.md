# Frontend/Backend Separation Summary

## ✅ What Was Changed

The application has been separated into **two independent services** in Kubernetes:

### 1. **Backend Service** (Flask API)
- **Deployment**: `disease-detector-backend`
- **Service**: `disease-detector-backend-service` (ClusterIP - internal only)
- **Image**: `varshayamsani/disease-detector-backend:latest`
- **Port**: 5001
- **Dockerfile**: `Dockerfile.backend`
- **Files**: Only `app.py` and backend code (no templates/static)

### 2. **Frontend Service** (Nginx)
- **Deployment**: `disease-detector-frontend`
- **Service**: `disease-detector-frontend-service` (LoadBalancer - external)
- **Image**: `varshayamsani/disease-detector-frontend:latest`
- **Port**: 80
- **Dockerfile**: `Dockerfile.frontend`
- **Files**: Static files, templates, nginx config

## 📁 New Files Created

### Kubernetes Manifests
- `k8s/backend-deployment.yaml` - Backend deployment
- `k8s/backend-service.yaml` - Backend service (ClusterIP)
- `k8s/backend-hpa.yaml` - Backend autoscaling
- `k8s/frontend-deployment.yaml` - Frontend deployment
- `k8s/frontend-service.yaml` - Frontend service (LoadBalancer)
- `k8s/frontend-hpa.yaml` - Frontend autoscaling
- `k8s/frontend-nginx-configmap.yaml` - Nginx configuration

### Dockerfiles
- `Dockerfile.backend` - Backend-only image
- `Dockerfile.frontend` - Frontend Nginx image

### Configuration
- `nginx.conf` - Nginx configuration with API proxying

### Documentation
- `MICROSERVICES_ARCHITECTURE.md` - Complete architecture guide

## 🔄 Updated Files

### Jenkinsfile
- Now builds **both** backend and frontend images in parallel
- Pushes both images to Docker Hub
- Deploys both services to Kubernetes
- Health checks both services

### JavaScript (main.js)
- Added `API_BASE` constant for dynamic API routing
- All fetch calls now use `${API_BASE}/...`
- Works for both local development and K8s deployment

### app.py
- Updated CORS configuration to allow frontend service
- Backend now only serves API endpoints (no template rendering)

## 🚀 How It Works

### Local Development
- `API_BASE = ''` (empty string)
- Frontend calls: `/predict`, `/patient/...`
- Works with Flask serving both frontend and backend

### Kubernetes Deployment
- `API_BASE = '/api'`
- Frontend calls: `/api/predict`, `/api/patient/...`
- Nginx proxies `/api/*` → `backend-service:5001/*`
- Backend only accessible internally

## 📊 Architecture Benefits

1. **Independent Scaling**: Frontend and backend scale separately
2. **Security**: Backend not directly exposed
3. **Resource Optimization**: Frontend needs minimal resources
4. **Technology Flexibility**: Can swap frontend/backend independently
5. **Better Caching**: Static files cached by Nginx
6. **Production Ready**: Follows microservices best practices

## 🎯 Next Steps

1. **Build Images**:
   ```bash
   docker build -f Dockerfile.backend -t varshayamsani/disease-detector-backend:latest .
   docker build -f Dockerfile.frontend -t varshayamsani/disease-detector-frontend:latest .
   ```

2. **Push to Docker Hub**:
   ```bash
   docker push varshayamsani/disease-detector-backend:latest
   docker push varshayamsani/disease-detector-frontend:latest
   ```

3. **Deploy to Kubernetes**:
   ```bash
   kubectl apply -f k8s/backend-deployment.yaml
   kubectl apply -f k8s/backend-service.yaml
   kubectl apply -f k8s/frontend-deployment.yaml
   kubectl apply -f k8s/frontend-service.yaml
   kubectl apply -f k8s/frontend-nginx-configmap.yaml
   kubectl apply -f k8s/backend-hpa.yaml
   kubectl apply -f k8s/frontend-hpa.yaml
   ```

4. **Verify**:
   ```bash
   kubectl get pods -n disease-detector
   kubectl get svc -n disease-detector
   ```

## 📝 Important Notes

- **Old deployment files** (`deployment.yaml`, `service.yaml`) are still there but not used
- **Jenkins pipeline** now builds and deploys both services
- **Local development** still works with single Flask app
- **Kubernetes deployment** uses separate services

See `MICROSERVICES_ARCHITECTURE.md` for complete details!

