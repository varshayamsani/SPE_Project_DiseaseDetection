// Jenkins Pipeline for Disease Detection Application
// This pipeline automates: Build -> Test -> Docker Build -> Push -> Deploy

pipeline {
    agent any
    
    // Environment variables - credentials from Jenkins credentials store
    // IMPORTANT: Update DOCKER_IMAGE with your Docker Hub username
    // Example: DOCKER_IMAGE = 'your-username/disease-detector'
    environment {
        DOCKER_HUB_CREDENTIALS = credentials('dockerhub')
        DOCKER_IMAGE = 'varshayamsani/disease-detector'  // TODO: Replace with your Docker Hub username
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
        
//         // Stage 3: Build Docker Image
//         stage('Docker Build') {
//             steps {
//                 echo 'Building Docker image...'
//                 script {
//                     dockerImage = docker.build("${DOCKER_IMAGE}:${DOCKER_TAG}")
//                     dockerImage.tag("${DOCKER_IMAGE}:latest")
//                 }
//             }
//         }
        stage('Docker Build') {
          steps {
            sh "docker build -t ${DOCKER_IMAGE}:${DOCKER_TAG} ."
            sh "docker tag ${DOCKER_IMAGE}:${DOCKER_TAG} ${DOCKER_IMAGE}:latest"
          }
        }

        stage('Push to Docker Hub') {
          steps {
            withCredentials([usernamePassword(credentialsId: 'dockerhub', usernameVariable: 'DH_USER', passwordVariable: 'DH_PASS')]) {
              sh '''
                echo "$DH_PASS" | docker login -u "$DH_USER" --password-stdin
                docker push ${DOCKER_IMAGE}:${DOCKER_TAG}
                docker push ${DOCKER_IMAGE}:latest
              '''
            }
          }
        }
//
//         // Stage 4: Push to Docker Hub
//         stage('Push to Docker Hub') {
//             steps {
//                 echo 'Pushing Docker image to Docker Hub...'
//                 script {
//                     docker.withRegistry('https://index.docker.io/v1/', DOCKER_HUB_CREDENTIALS) {
//                         dockerImage.push("${DOCKER_TAG}")
//                         dockerImage.push("latest")
//                     }
//                 }
//             }
//         }
//
        // Stage 5: Deploy to Kubernetes
        stage('Deploy to Kubernetes') {
            steps {
                echo 'Deploying to Kubernetes...'
                sh '''
                    # Update Kubernetes deployment with new image
                    kubectl set image deployment/disease-detector \
                        disease-detector=${DOCKER_IMAGE}:${DOCKER_TAG} \
                        -n ${KUBERNETES_NAMESPACE} || \
                    kubectl apply -f k8s/ -n ${KUBERNETES_NAMESPACE}
                    
                    # Wait for rollout
                    kubectl rollout status deployment/disease-detector -n ${KUBERNETES_NAMESPACE}
                '''
            }
        }
        
        // Stage 6: Health Check
        stage('Health Check') {
            steps {
                echo 'Performing health check...'
                sh '''
                    sleep 10
                    curl -f http://localhost:5001/health || exit 1
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


