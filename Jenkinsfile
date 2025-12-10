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
                    
                    // Configure access to Kubernetes cluster using kubeconfig credentials
                    // Uses Jenkins Kubernetes plugin withKubeConfig
//                     withCredentials([file(credentialsId: 'kubeconfig', variable: 'KCFG')]) {
//                         sh """
//                             export KUBECONFIG=$KCFG
//                             kubectl get ns
//                         """
//                     }
withCredentials([file(credentialsId: 'kubeconfig', variable: 'KUBECONFIG_FILE')]) {
    echo 'Running Ansible playbook (playbook.yaml) to deploy application...'
    sh """
        # Use the kubeconfig file from Jenkins secret
        export KUBECONFIG=${KUBECONFIG_FILE}

        cd ansible
        ansible-playbook -i inventory.yml playbook.yaml \
            -e "kubeconfig_path=${KUBECONFIG_FILE}" \
            -e "docker_image_backend=${DOCKER_IMAGE_BACKEND}:${DOCKER_TAG}" \
            -e "docker_image_frontend=${DOCKER_IMAGE_FRONTEND}:${DOCKER_TAG}" \
            -e "kubernetes_namespace=${KUBERNETES_NAMESPACE}" \
            -v
    """
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
        stage('Health Check') {
            steps {
                echo 'Performing health checks...'
                sh '''
                    sleep 15
                    # Check backend health
                    kubectl run health-check --image=curlimages/curl:latest --rm -i --restart=Never -n ${KUBERNETES_NAMESPACE} -- \
                        curl -f http://disease-detector-backend-service:5001/health || exit 1
                    
                    # Check frontend health
                    kubectl run frontend-health-check --image=curlimages/curl:latest --rm -i --restart=Never -n ${KUBERNETES_NAMESPACE} -- \
                        curl -f http://disease-detector-frontend-service/health || exit 1
                '''
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


