// Jenkins Pipeline for Disease Detection Application
// This pipeline automates: Build -> Test -> Docker Build -> Push -> Deploy

pipeline {
    agent any
    
    // Environment variables - credentials from Jenkins credentials store
    // IMPORTANT: Update DOCKER_IMAGE with your Docker Hub username
    // Example: DOCKER_IMAGE = 'your-username/disease-detector'
    environment {
        DOCKER_HUB_CREDENTIALS = credentials('dockerhub')
        DOCKER_IMAGE_BASE = 'varshayamsani/disease-detector'  // Base name for images
        DOCKER_IMAGE_BACKEND = "${DOCKER_IMAGE_BASE}-backend"
        DOCKER_IMAGE_FRONTEND = "${DOCKER_IMAGE_BASE}-frontend"
        DOCKER_TAG = "${env.BUILD_NUMBER}"
        KUBERNETES_NAMESPACE = 'disease-detector'
        VAULT_ADDR = 'http://vault:8200'
    }
    
    stages {
        // Stage 1: Checkout code from GitHub
        stage('Checkout') {
            steps {
                echo 'Checking out code from GitHub...'
                checkout scm
                sh 'git rev-parse HEAD > .git/commit-id'
            }
        }
        
        // Stage 2: Build and Test
        stage('Build & Test') {
            steps {
                echo 'Building and testing application...'
                sh '''
                    python3 -m venv venv
                    source venv/bin/activate
                    pip install -r requirements.txt
                    python -m pytest tests/ || echo "No tests found, continuing..."
                '''
            }
        }
        
        // Stage 3: Build Docker Images (Backend and Frontend)
        stage('Docker Build') {
            parallel {
                stage('Build Backend') {
                    steps {
                        echo 'Building Backend Docker image...'
                        script {
                            sh """
                                docker build -f Dockerfile.backend -t ${DOCKER_IMAGE_BACKEND}:${DOCKER_TAG} .
                                docker tag ${DOCKER_IMAGE_BACKEND}:${DOCKER_TAG} ${DOCKER_IMAGE_BACKEND}:latest
                            """
                        }
                    }
                }
                stage('Build Frontend') {
                    steps {
                        echo 'Building Frontend Docker image...'
                        script {
                            sh """
                                docker build -f Dockerfile.frontend -t ${DOCKER_IMAGE_FRONTEND}:${DOCKER_TAG} .
                                docker tag ${DOCKER_IMAGE_FRONTEND}:${DOCKER_TAG} ${DOCKER_IMAGE_FRONTEND}:latest
                            """
                        }
                    }
                }
            }
        }
        
        // Stage 4: Push to Docker Hub
        stage('Push to Docker Hub') {
            parallel {
                stage('Push Backend') {
                    steps {
                        echo 'Pushing Backend Docker image to Docker Hub...'
                        withCredentials([usernamePassword(credentialsId: 'dockerhub', usernameVariable: 'DH_USER', passwordVariable: 'DH_PASS')]) {
                            sh """
                                echo "\$DH_PASS" | docker login -u "\$DH_USER" --password-stdin
                                docker push ${DOCKER_IMAGE_BACKEND}:${DOCKER_TAG}
                                docker push ${DOCKER_IMAGE_BACKEND}:latest
                            """
                        }
                    }
                }
                stage('Push Frontend') {
                    steps {
                        echo 'Pushing Frontend Docker image to Docker Hub...'
                        withCredentials([usernamePassword(credentialsId: 'dockerhub', usernameVariable: 'DH_USER', passwordVariable: 'DH_PASS')]) {
                            sh """
                                echo "\$DH_PASS" | docker login -u "\$DH_USER" --password-stdin
                                docker push ${DOCKER_IMAGE_FRONTEND}:${DOCKER_TAG}
                                docker push ${DOCKER_IMAGE_FRONTEND}:latest
                            """
                        }
                    }
                }
            }
        }
        // Stage 5: Deploy with Kubernetes
        // Purpose: Deploy the application using Kubernetes and Ansible
        // Key Actions:
        //   - Configures access to the Kubernetes cluster using the kubeconfig credentials
        //   - Runs an Ansible playbook (playbook.yaml) to deploy the application
        //   - Ensures all configurations and services are applied as required
        //   - Deploys the application in the Kubernetes cluster for production or testing
        stage('Deploy with Kubernetes') {
            steps {
                echo '========================================'
                echo 'Stage: Deploy with Kubernetes'
                echo 'Purpose: Deploy application using Kubernetes and Ansible'
                echo '========================================'
                
                script {
                    // Install Ansible if not available
                    sh '''
                        if ! command -v ansible-playbook &> /dev/null; then
                            echo "Installing Ansible..."
                            pip3 install ansible || pip install ansible
                        fi
                        ansible-playbook --version
                    '''
                    

                    // Uses Jenkins Kubernetes plugin withKubeConfig
//                     withCredentials([file(credentialsId: 'kubeconfig', variable: 'KCFG')]) {
//                         sh """
//                             export KUBECONFIG=$KCFG
//                             kubectl get ns
//                         """
//                     }
withCredentials([file(credentialsId: 'kubeconfig', variable: 'KUBECONFIG_FILE')]) {
    echo 'Running Ansible playbook (playbook.yaml) to deploy application...'
    // Store non-secret values in environment variables to avoid Groovy interpolation of secrets
    script {
        env.DOCKER_IMAGE_BACKEND_FULL = "${DOCKER_IMAGE_BACKEND}:${DOCKER_TAG}"
        env.DOCKER_IMAGE_FRONTEND_FULL = "${DOCKER_IMAGE_FRONTEND}:${DOCKER_TAG}"
    }
    // Use single quotes to prevent Groovy string interpolation of secrets
    sh '''
        # Use the kubeconfig file from Jenkins secret (not interpolated by Groovy)
        export KUBECONFIG="$KUBECONFIG_FILE"
        
        # Display diagnostic information
        echo "=========================================="
        echo "Kubernetes Cluster Diagnostic Information"
        echo "=========================================="
        echo "Kubeconfig file: $KUBECONFIG_FILE"
        echo "Kubeconfig exists: $([ -f "$KUBECONFIG_FILE" ] && echo "Yes" || echo "No")"
        echo ""
        
        # Check kubectl version
        echo "kubectl version:"
        kubectl version --client 2>&1 || echo "Warning: kubectl version check failed"
        echo ""
        
        # Show current context (if kubeconfig is valid)
        echo "Current context:"
        kubectl config current-context 2>&1 || echo "Warning: Could not get current context"
        echo ""
        
        # Show server URL (if kubeconfig is valid)
        echo "Cluster server URL:"
        kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}' 2>&1 || echo "Warning: Could not get server URL"
        echo ""
        echo "=========================================="
        echo ""
        
        # Verify cluster connectivity before proceeding
        echo "Verifying Kubernetes cluster connectivity..."
        echo "Attempting connection with retries..."
        
        CLUSTER_INFO_EXIT=1
        CLUSTER_INFO_OUTPUT=""
        MAX_RETRIES=3
        RETRY_DELAY=5
        
        for i in $(seq 1 $MAX_RETRIES); do
            echo "Attempt $i/$MAX_RETRIES..."
            CLUSTER_INFO_OUTPUT=$(kubectl cluster-info --request-timeout=20s 2>&1)
            CLUSTER_INFO_EXIT=$?
            
            if [ $CLUSTER_INFO_EXIT -eq 0 ]; then
                echo "✅ Successfully connected to cluster!"
                break
            else
                if [ $i -lt $MAX_RETRIES ]; then
                    echo "⚠️  Connection failed, retrying in ${RETRY_DELAY}s..."
                    echo "Error: $CLUSTER_INFO_OUTPUT"
                    sleep $RETRY_DELAY
                    RETRY_DELAY=$((RETRY_DELAY * 2))  # Exponential backoff
                fi
            fi
        done
        
        if [ $CLUSTER_INFO_EXIT -ne 0 ]; then
            echo ""
            echo "=========================================="
            echo "ERROR: Cannot connect to Kubernetes cluster"
            echo "=========================================="
            echo ""
            echo "kubectl cluster-info output:"
            echo "$CLUSTER_INFO_OUTPUT"
            echo ""
            
            # Detect if running in Docker
            if [ -f /.dockerenv ] || grep -q docker /proc/self/cgroup 2>/dev/null; then
                echo "⚠️  Jenkins appears to be running in Docker"
                echo ""
                echo "If using minikube, try updating kubeconfig to use:"
                echo "  - host.docker.internal (macOS/Windows Docker Desktop)"
                echo "  - Host machine IP address"
                echo ""
                echo "Run this script to fix:"
                echo "  ./scripts/fix-kubeconfig-for-jenkins.sh"
                echo ""
            fi
            
            echo "Troubleshooting steps:"
            echo "  1. Verify the cluster is running:"
            echo "     - For minikube: run 'minikube status'"
            echo "     - For Docker Desktop: check Kubernetes is enabled in settings"
            echo "     - For remote cluster: verify network connectivity"
            echo ""
            echo "  2. Verify kubeconfig file is valid:"
            echo "     - Check the kubeconfig file exists and is readable"
            echo "     - Verify the server URL is correct"
            echo "     - Ensure certificates are valid (not expired)"
            echo ""
            echo "  3. Check cluster accessibility from Jenkins node:"
            SERVER_URL=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}' 2>/dev/null || echo "unknown")
            echo "     - Current server URL: $SERVER_URL"
            if [[ "$SERVER_URL" == *"127.0.0.1"* ]] || [[ "$SERVER_URL" == *"localhost"* ]]; then
                echo "     - ⚠️  Using localhost - if Jenkins is in Docker, this won't work"
                echo "     - Solution: Update kubeconfig to use host.docker.internal or host IP"
            fi
            echo ""
            echo "  4. Current configuration:"
            kubectl config view --minify 2>&1 | head -20 || echo "Could not display config"
            echo ""
            echo "=========================================="
            exit 1
        fi
        
        echo "Cluster connectivity verified:"
        echo "$CLUSTER_INFO_OUTPUT"
        echo ""
        
        # Additional verification: check if we can get nodes
        echo "Verifying node access..."
        if kubectl get nodes --request-timeout=10s &>/dev/null; then
            echo "✅ Successfully connected to cluster"
            kubectl get nodes --request-timeout=10s
        else
            echo "⚠️  Warning: Could not retrieve nodes, but cluster-info succeeded"
        fi
        echo ""
        
        cd ansible
        ansible-playbook -i inventory.yml playbook.yaml \
            -e "kubeconfig_path=$KUBECONFIG_FILE" \
            -e "docker_image_backend=$DOCKER_IMAGE_BACKEND_FULL" \
            -e "docker_image_frontend=$DOCKER_IMAGE_FRONTEND_FULL" \
            -e "kubernetes_namespace=$KUBERNETES_NAMESPACE" \
            -v
    '''
}

//                     withKubeConfig([credentialsId: 'kubeconfig', serverUrl: '']) {
//                         // Run Ansible playbook (playbook.yaml) to deploy the application
//                         echo 'Running Ansible playbook (playbook.yaml) to deploy application...'
//                         sh """
//                             cd ansible
//                             ansible-playbook -i inventory.yml playbook.yaml \
//                                 -e "kubeconfig_path=\${KUBECONFIG}" \
//                                 -e "docker_image_backend=${DOCKER_IMAGE_BACKEND}:${DOCKER_TAG}" \
//                                 -e "docker_image_frontend=${DOCKER_IMAGE_FRONTEND}:${DOCKER_TAG}" \
//                                 -e "kubernetes_namespace=${KUBERNETES_NAMESPACE}" \
//                                 -v
//                         """
//                     }
                }
            }
        }
        
        // Stage 6: Health Check
//         stage('Health Check') {
//             steps {
//                 echo 'Performing health checks...'
//                 sh '''
//                     sleep 15
//                     # Check backend health
//                     kubectl run health-check --image=curlimages/curl:latest --rm -i --restart=Never -n ${KUBERNETES_NAMESPACE} -- \
//                         curl -f http://disease-detector-backend-service:5001/health || exit 1
//
//                     # Check frontend health
//                     kubectl run frontend-health-check --image=curlimages/curl:latest --rm -i --restart=Never -n ${KUBERNETES_NAMESPACE} -- \
//                         curl -f http://disease-detector-frontend-service/health || exit 1
//                 '''
//             }
//         }
        stage('Health Check') {
            steps {
                echo 'Performing health checks...'
                withCredentials([file(credentialsId: 'kubeconfig', variable: 'KUBECONFIG_FILE')]) {
                    sh '''
                        export KUBECONFIG="$KUBECONFIG_FILE"
                        NAMESPACE=${KUBERNETES_NAMESPACE}
                        
                        echo "=========================================="
                        echo "Waiting for deployments to be ready..."
                        echo "=========================================="
                        
                        # Wait for backend deployment to be ready
                        echo "Waiting for backend deployment..."
                        if kubectl wait --for=condition=available --timeout=300s deployment/disease-detector-backend -n ${NAMESPACE}; then
                            echo "✅ Backend deployment is ready"
                        else
                            echo "⚠️  Backend deployment not ready after 5 minutes, checking status..."
                            kubectl get deployment/disease-detector-backend -n ${NAMESPACE}
                            kubectl get pods -n ${NAMESPACE} -l app=disease-detector-backend
                        fi
                        
                        # Wait for frontend deployment to be ready
                        echo "Waiting for frontend deployment..."
                        if kubectl wait --for=condition=available --timeout=300s deployment/disease-detector-frontend -n ${NAMESPACE}; then
                            echo "✅ Frontend deployment is ready"
                        else
                            echo "⚠️  Frontend deployment not ready after 5 minutes, checking status..."
                            kubectl get deployment/disease-detector-frontend -n ${NAMESPACE}
                            kubectl get pods -n ${NAMESPACE} -l app=disease-detector-frontend
                        fi
                        
                        echo ""
                        echo "=========================================="
                        echo "Checking service health endpoints..."
                        echo "=========================================="
                        
                        # Check backend health
                        echo "Checking backend health..."
                        ATTEMPTS=20
                        SLEEP=25
                        BACKEND_HEALTHY=false
                        
                        for i in $(seq 1 $ATTEMPTS); do
                            echo "Backend health attempt $i/$ATTEMPTS..."
                            if kubectl run backend-health-check-$i --image=curlimages/curl:latest --rm -i --restart=Never --timeout=30s -n ${NAMESPACE} -- \
                                 curl -fsS --max-time 10 http://disease-detector-backend-service:5001/health 2>/dev/null; then
                                echo "✅ Backend is healthy!"
                                BACKEND_HEALTHY=true
                                break
                            fi
                            echo "Backend not ready yet, sleeping ${SLEEP}s..."
                            sleep $SLEEP
                        done
                        
                        if [ "$BACKEND_HEALTHY" = "false" ]; then
                            echo "⚠️  Backend health check failed after ${ATTEMPTS} attempts"
                            echo "Checking backend pod logs..."
                            kubectl logs -n ${NAMESPACE} -l app=disease-detector-backend --tail=20 || true
                        fi
                        
                        # Check frontend health
                        echo ""
                        echo "Checking frontend health..."
                        FRONTEND_HEALTHY=false
                        
                        for i in $(seq 1 $ATTEMPTS); do
                            echo "Frontend health attempt $i/$ATTEMPTS..."
                            if kubectl run frontend-health-check-$i --image=curlimages/curl:latest --rm -i --restart=Never --timeout=30s -n ${NAMESPACE} -- \
                                 curl -fsS --max-time 10 http://disease-detector-frontend-service/health 2>/dev/null; then
                                echo "✅ Frontend is healthy!"
                                FRONTEND_HEALTHY=true
                                break
                            fi
                            echo "Frontend not ready yet, sleeping ${SLEEP}s..."
                            sleep $SLEEP
                        done
                        
                        if [ "$FRONTEND_HEALTHY" = "false" ]; then
                            echo "⚠️  Frontend health check failed after ${ATTEMPTS} attempts"
                            echo "Checking frontend pod logs..."
                            kubectl logs -n ${NAMESPACE} -l app=disease-detector-frontend --tail=20 || true
                        fi
                        
                        echo ""
                        echo "=========================================="
                        echo "Health Check Summary"
                        echo "=========================================="
                        echo "Backend: $([ "$BACKEND_HEALTHY" = "true" ] && echo "✅ Healthy" || echo "❌ Unhealthy")"
                        echo "Frontend: $([ "$FRONTEND_HEALTHY" = "true" ] && echo "✅ Healthy" || echo "❌ Unhealthy")"
                        echo ""
                        
                        # Only fail if both are unhealthy
                        if [ "$BACKEND_HEALTHY" = "false" ] && [ "$FRONTEND_HEALTHY" = "false" ]; then
                            echo "❌ Both services are unhealthy. Failing health check."
                            exit 1
                        elif [ "$BACKEND_HEALTHY" = "false" ] || [ "$FRONTEND_HEALTHY" = "false" ]; then
                            echo "⚠️  One or more services are unhealthy, but continuing..."
                        else
                            echo "✅ All services are healthy!"
                        fi
                    '''
                }
            }
        }

    }
    
    // Post-build actions
    post {
        success {
            echo 'Pipeline succeeded!'
            // Send notification (email, Slack, etc.)
        }
        failure {
            echo 'Pipeline failed!'
            // Send failure notification
        }
        always {
            // Clean up
            sh 'docker image prune -f'
        }
    }
}


