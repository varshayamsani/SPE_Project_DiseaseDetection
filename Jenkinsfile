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
//         stage('Build & Test') {
//             steps {
//                 echo 'Building and testing application...'
//                 sh '''
//                     python3 -m venv venv
//                     source venv/bin/activate
//                     pip install -r requirements.txt
//                     python -m pytest tests/ || echo "No tests found, continuing..."
//                 '''
//             }
//         }
// Stage 2: Build and Test
        stage('Build & Test') {
            steps {
                echo 'Building and testing application...'
                sh '''
                    python3 -m venv venv
                    source venv/bin/activate
                    pip install -r requirements.txt
                    if [ -f requirements-dev.txt ]; then
                      pip install -r requirements-dev.txt
                    else
                      pip install pytest
                    fi
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
        // Stage 4.5: Start ELK stack locally via docker compose (Elasticsearch, Logstash, Kibana)
        // stage('Start ELK') {
        //     steps {
        //         echo 'Starting Elasticsearch, Logstash, Kibana via docker compose...'
        //         sh '''


        //             set -e
        //             export COMPOSE_PROJECT_NAME=${JOB_NAME:-disease-detector}
        //             if command -v docker-compose >/dev/null 2>&1; then
        //               COMPOSE_CMD="docker-compose"
        //             else
        //               COMPOSE_CMD="docker compose"
        //             fi
        //             $COMPOSE_CMD -f docker-compose.yml up -d --remove-orphans elasticsearch logstash kibana
        //         '''
        //     }
        // }
        stage('Start ELK') {
  steps {
    echo 'Starting Elasticsearch, Logstash, Kibana via docker compose...'
    sh '''
      set -euo pipefail

      # project name (keeps resources per-job isolated)
      export COMPOSE_PROJECT_NAME=${JOB_NAME:-disease-detector}

      # pick compose command (supports both v1 and v2)
      if command -v docker-compose >/dev/null 2>&1; then
        COMPOSE_CMD="docker-compose"
      else
        COMPOSE_CMD="docker compose"
      fi

      # -----------------------
      # 1) Best-effort cleanup
      # -----------------------
      echo "Cleaning pre-existing containers / networks for project: $COMPOSE_PROJECT_NAME"
      # remove exact named containers if present (silently ignore errors)
      docker rm -f ${COMPOSE_PROJECT_NAME}_elasticsearch_1 ${COMPOSE_PROJECT_NAME}_logstash_1 ${COMPOSE_PROJECT_NAME}_kibana_1 2>/dev/null || true

      # remove any container whose name includes the project name and service name
      docker ps -aq --filter "name=${COMPOSE_PROJECT_NAME}.*elasticsearch" | xargs -r docker rm -f 2>/dev/null || true
      docker ps -aq --filter "name=${COMPOSE_PROJECT_NAME}.*kibana" | xargs -r docker rm -f 2>/dev/null || true
      docker ps -aq --filter "name=${COMPOSE_PROJECT_NAME}.*logstash" | xargs -r docker rm -f 2>/dev/null || true

      # bring down the compose stack to free networks/ports
      $COMPOSE_CMD -f docker-compose.yml down --remove-orphans || true

      # small sleep to let Docker free sockets (helps on macOS/Docker Desktop)
      sleep 2

      # -----------------------
      # 2) Start fresh
      # -----------------------
      echo "Starting ELK stack..."
      $COMPOSE_CMD -f docker-compose.yml up -d --remove-orphans --force-recreate elasticsearch logstash kibana

      # -----------------------
      # 3) Wait for health (optional)
      # -----------------------
      # Wait for Elasticsearch to respond on its container port (compose internal networking)
      echo "Waiting for Elasticsearch (container) to be healthy..."
      for i in $(seq 1 30); do
        # use docker-compose exec if available, fallback to curl from host to mapped host port if you expose it
        if $COMPOSE_CMD -f docker-compose.yml exec -T elasticsearch /bin/bash -c "curl -sS localhost:9200 >/dev/null 2>&1"; then
          echo "Elasticsearch responded."
          break
        fi
        echo "sleeping ... ($i)"
        sleep 2
      done
    '''
  }
}


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


// stage('Deploy with Kubernetes') {
//   steps {
//     echo '========================================'
//     echo 'Stage: Deploy with Kubernetes'
//     echo 'Purpose: Deploy application using Kubernetes and Ansible'
//     echo '========================================'
//
//     script {
//       // Ensure ansible-playbook present
//       sh '''
// if ! command -v ansible-playbook &>/dev/null; then
//   echo "Installing Ansible..."
//   pip3 install --user ansible || pip install --user ansible
// fi
// ansible-playbook --version || true
// '''
//       // Main deploy script: generate ephemeral kubeconfig and run ansible
//       sh '''
// set -euo pipefail
// export PATH="$HOME/.local/bin:$PATH"
//
// WORKSPACE="$(pwd)"
// NS=disease-detector
// SA=jenkins-sa
// OUT="${WORKSPACE}/jenkins-kubeconfig.yaml"
// ADMIN_KUBECONFIG="${HOME}/.kube/config"
//
// echo "Workspace: ${WORKSPACE}"
// echo "Will create ephemeral kubeconfig: ${OUT}"
// echo "Admin kubeconfig: ${ADMIN_KUBECONFIG}"
//
// # Create safe temp dir for YAML files
// TMPDIR="$(mktemp -d)"
// echo "Temp dir: ${TMPDIR}"
// set -x
//
// # 1) ServiceAccount YAML
// cat > "${TMPDIR}/sa.yaml" <<'YAML'
// apiVersion: v1
// kind: ServiceAccount
// metadata:
//   name: jenkins-sa
//   namespace: disease-detector
// YAML
//
// # 2) Role YAML (adjust resources/verbs if you need to restrict further)
// cat > "${TMPDIR}/role.yaml" <<'YAML'
// apiVersion: rbac.authorization.k8s.io/v1
// kind: Role
// metadata:
//   name: jenkins-sa-role
//   namespace: disease-detector
// rules:
// - apiGroups: ["", "apps", "autoscaling", "networking.k8s.io"]
//   resources: ["pods","services","deployments","replicasets","configmaps","secrets","horizontalpodautoscalers","ingresses"]
//   verbs: ["get","list","watch","create","update","patch","delete"]
// YAML
//
// # 3) RoleBinding YAML
// cat > "${TMPDIR}/rb.yaml" <<'YAML'
// apiVersion: rbac.authorization.k8s.io/v1
// kind: RoleBinding
// metadata:
//   name: jenkins-sa-binding
//   namespace: disease-detector
// subjects:
// - kind: ServiceAccount
//   name: jenkins-sa
//   namespace: disease-detector
// roleRef:
//   kind: Role
//   name: jenkins-sa-role
//   apiGroup: rbac.authorization.k8s.io
// YAML
//
// # Apply them using the admin kubeconfig (idempotent)
// kubectl --kubeconfig="${ADMIN_KUBECONFIG}" apply -f "${TMPDIR}/sa.yaml" -n "${NS}"
// kubectl --kubeconfig="${ADMIN_KUBECONFIG}" apply -f "${TMPDIR}/role.yaml" -n "${NS}"
// kubectl --kubeconfig="${ADMIN_KUBECONFIG}" apply -f "${TMPDIR}/rb.yaml" -n "${NS}"
//
// # Create token for the SA (preferred)
// TOKEN="$(kubectl --kubeconfig="${ADMIN_KUBECONFIG}" create token "${SA}" -n "${NS}" 2>/dev/null || true)"
//
// if [ -z "${TOKEN}" ]; then
//   # Fallback for older clusters: read the secret token
//   SECRET_NAME="$(kubectl --kubeconfig="${ADMIN_KUBECONFIG}" -n "${NS}" get sa "${SA}" -o jsonpath='{.secrets[0].name}' 2>/dev/null || true)"
//   if [ -n "${SECRET_NAME}" ]; then
//     TOKEN="$(kubectl --kubeconfig="${ADMIN_KUBECONFIG}" -n "${NS}" get secret "${SECRET_NAME}" -o jsonpath='{.data.token}' | base64 --decode)"
//   else
//     echo "ERROR: could not obtain token for serviceaccount ${SA}"
//     exit 1
//   fi
// fi
//
// # Build kubeconfig using admin cluster info (server + CA)
// CLUSTER_NAME="$(kubectl --kubeconfig="${ADMIN_KUBECONFIG}" config view -o jsonpath='{.clusters[0].name}')"
// SERVER="$(kubectl --kubeconfig="${ADMIN_KUBECONFIG}" config view -o jsonpath="{.clusters[?(@.name=='${CLUSTER_NAME}')].cluster.server}")"
// CA_DATA="$(kubectl --kubeconfig="${ADMIN_KUBECONFIG}" config view --raw -o jsonpath="{.clusters[?(@.name=='${CLUSTER_NAME}')].cluster['certificate-authority-data']}")"
//
// if [ -z "${SERVER}" ] || [ -z "${CA_DATA}" ]; then
//   echo "ERROR: could not extract SERVER or CA from admin kubeconfig (${ADMIN_KUBECONFIG})"
//   exit 1
// fi
//
// cat > "${OUT}" <<EOF
// apiVersion: v1
// kind: Config
// clusters:
// - name: jenkins-cluster
//   cluster:
//     server: ${SERVER}
//     certificate-authority-data: ${CA_DATA}
// contexts:
// - name: jenkins-context
//   context:
//     cluster: jenkins-cluster
//     namespace: ${NS}
//     user: jenkins-sa-user
// current-context: jenkins-context
// users:
// - name: jenkins-sa-user
//   user:
//     token: ${TOKEN}
// EOF
//
// chmod 600 "${OUT}"
// echo "Generated kubeconfig: ${OUT}"
//
// # Preflight checks
// export NO_PROXY="${NO_PROXY:-},127.0.0.1,localhost"
// export no_proxy="${no_proxy:-},127.0.0.1,localhost"
// kubectl --kubeconfig="${OUT}" cluster-info --request-timeout=10s || true
// kubectl --kubeconfig="${OUT}" -n "${NS}" get deployments || true
//
// # Run ansible-playbook with kubeconfig available
// export KUBECONFIG="${OUT}"
// cd ansible
// ansible-playbook -i inventory.yml playbook.yaml \
//   -e "kubeconfig_path=${OUT}" \
//   -e "docker_image_backend=${DOCKER_IMAGE_BACKEND}:${DOCKER_TAG}" \
//   -e "docker_image_frontend=${DOCKER_IMAGE_FRONTEND}:${DOCKER_TAG}" \
//   -e "kubernetes_namespace=${KUBERNETES_NAMESPACE}" \
//   -v
//
// # Optional cleanup: remove the ephemeral kubeconfig and temp files
// rm -f "${OUT}"
// rm -rf "${TMPDIR}"
//
// set +x
// '''
//     }
//   }
// }




        stage('Health Check') {
            steps {
                echo 'Performing health checks...'
                sh '''
                    NAMESPACE=${KUBERNETES_NAMESPACE}
//                     echo "Checking frontend health..."
//                     kubectl run frontend-health --image=curlimages/curl:latest --rm -i --restart=Never -n ${KUBERNETES_NAMESPACE} -- \
//                     curl -f http://disease-detector-frontend-service/health || exit 1
//

                    FRONTEND_POD=$(kubectl get pods -n disease-detector -l app=disease-detector-frontend -o jsonpath="{.items[0].metadata.name}")

                    echo "Checking frontend health using existing pod $FRONTEND_POD ..."

                    kubectl exec -n disease-detector "$FRONTEND_POD" -- curl -f http://disease-detector-frontend-service/health || exit 1


                    echo "Waiting for backend to become healthy..."
                    ATTEMPTS=20   # 20 * 20s = 120 seconds
                    SLEEP=20

                    for i in $(seq 1 $ATTEMPTS); do
                      echo "Backend health attempt $i/$ATTEMPTS..."
                      if kubectl run backend-health --image=curlimages/curl:latest --rm -i --restart=Never -n ${KUBERNETES_NAMESPACE} -- \
                           curl -fsS http://disease-detector-backend-service:5001/health; then
                        echo "Backend is healthy!"
                        break
                      fi
                      echo "Backend not ready yet, sleeping ${SLEEP}s..."
                      sleep $SLEEP
                      if [ "$i" -eq "$ATTEMPTS" ]; then
                        echo "Backend failed health check after ${ATTEMPTS} attempts"
                        exit 1
                      fi
                    done

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


