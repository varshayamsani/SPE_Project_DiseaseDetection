# Microservices Architecture - Frontend/Backend Separation

## Overview

The application has been refactored into a proper microservices architecture with separate frontend and backend services.

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    Frontend Service                      │
│  ┌──────────────────────────────────────────────────┐  │
│  │  Nginx Container                                  │  │
│  │  - Serves static files (HTML, CSS, JS)            │  │
│  │  - Proxies /api/* requests to backend             │  │
│  │  - Port: 80                                       │  │
│  └──────────────────────────────────────────────────┘  │
│                    ↓ (HTTP requests)                    │
└─────────────────────────────────────────────────────────┘
                        ↓
┌─────────────────────────────────────────────────────────┐
│                    Backend Service                       │
│  ┌──────────────────────────────────────────────────┐  │
│  │  Flask API Container                              │  │
│  │  - REST API endpoints                            │  │
│  │  - ML model inference                            │  │
│  │  - Database operations                           │  │
│  │  - Port: 5001                                    │  │
│  └──────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────┘
```

## Services

### Frontend Service
- **Deployment**: `disease-detector-frontend`
- **Service**: `disease-detector-frontend-service` (LoadBalancer)
- **Image**: `varshayamsani/disease-detector-frontend:latest`
- **Port**: 80 (external access)
- **Replicas**: 2-5 (HPA enabled)
- **Technology**: Nginx serving static files

### Backend Service
- **Deployment**: `disease-detector-backend`
- **Service**: `disease-detector-backend-service` (ClusterIP - internal only)
- **Image**: `varshayamsani/disease-detector-backend:latest`
- **Port**: 5001 (internal cluster access)
- **Replicas**: 2-10 (HPA enabled)
- **Technology**: Flask API

## Benefits of Separation

1. **Independent Scaling**: Frontend and backend can scale independently
2. **Technology Flexibility**: Can use different technologies for each
3. **Security**: Backend not directly exposed, only through frontend proxy
4. **Resource Optimization**: Frontend needs fewer resources
5. **Deployment Independence**: Update frontend or backend separately
6. **Better Caching**: Static files cached by Nginx/CDN

## File Structure

### Backend Files
- `Dockerfile.backend` - Backend container image
- `app.py` - Flask API (no template rendering)
- `k8s/backend-deployment.yaml` - Backend K8s deployment
- `k8s/backend-service.yaml` - Backend K8s service
- `k8s/backend-hpa.yaml` - Backend autoscaling

### Frontend Files
- `Dockerfile.frontend` - Frontend container image
- `nginx.conf` - Nginx configuration
- `static/` - Static assets (CSS, JS)
- `templates/` - HTML templates
- `k8s/frontend-deployment.yaml` - Frontend K8s deployment
- `k8s/frontend-service.yaml` - Frontend K8s service
- `k8s/frontend-hpa.yaml` - Frontend autoscaling
- `k8s/frontend-nginx-configmap.yaml` - Nginx config as ConfigMap

## Deployment

### Build Images

```bash
# Build backend
docker build -f Dockerfile.backend -t varshayamsani/disease-detector-backend:latest .

# Build frontend
docker build -f Dockerfile.frontend -t varshayamsani/disease-detector-frontend:latest .
```

### Push to Docker Hub

```bash
docker push varshayamsani/disease-detector-backend:latest
docker push varshayamsani/disease-detector-frontend:latest
```

### Deploy to Kubernetes

```bash
# Apply all manifests
kubectl apply -f k8s/

# Or apply separately
kubectl apply -f k8s/backend-deployment.yaml
kubectl apply -f k8s/backend-service.yaml
kubectl apply -f k8s/frontend-deployment.yaml
kubectl apply -f k8s/frontend-service.yaml
kubectl apply -f k8s/backend-hpa.yaml
kubectl apply -f k8s/frontend-hpa.yaml
kubectl apply -f k8s/frontend-nginx-configmap.yaml
```

### Verify Deployment

```bash
# Check pods
kubectl get pods -n disease-detector

# Check services
kubectl get svc -n disease-detector

# Check deployments
kubectl get deployment -n disease-detector

# Check HPA
kubectl get hpa -n disease-detector
```

## Access Points

### Frontend (External)
- **Service**: `disease-detector-frontend-service`
- **Type**: LoadBalancer
- **Port**: 80
- **Access**: `http://<loadbalancer-ip>` or port-forward

### Backend (Internal Only)
- **Service**: `disease-detector-backend-service`
- **Type**: ClusterIP
- **Port**: 5001
- **Access**: Only from within cluster or via frontend proxy

## API Routing

Frontend Nginx proxies API requests:
- `/api/*` → `http://disease-detector-backend-service:5001/*`

Example:
- Frontend: `http://frontend-service/api/predict`
- Proxied to: `http://disease-detector-backend-service:5001/predict`

## Local Development

For local development, the frontend JavaScript automatically detects localhost and uses direct API calls (no `/api` prefix).

## CI/CD Pipeline

The Jenkins pipeline now:
1. Builds both backend and frontend images in parallel
2. Pushes both images to Docker Hub
3. Deploys both services to Kubernetes
4. Performs health checks on both services

## Migration Notes

The old monolithic deployment files are still available:
- `k8s/deployment.yaml` (old)
- `k8s/service.yaml` (old)

You can remove these after verifying the new architecture works.

## Troubleshooting

### Frontend can't reach backend
- Check backend service is running: `kubectl get svc -n disease-detector`
- Verify service name: `disease-detector-backend-service`
- Check nginx config in ConfigMap

### API calls failing
- Verify API_BASE is set correctly in JavaScript
- Check browser console for CORS errors
- Ensure backend CORS is configured for frontend service

### Images not found
- Verify images pushed to Docker Hub
- Check image names match in deployment files
- Ensure imagePullPolicy is set correctly

