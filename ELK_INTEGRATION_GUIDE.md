# ELK Integration Guide - Lightweight & Resource-Efficient

## Why ELK Caused Issues

**Problem**: Full ELK stack is resource-intensive:
- **Elasticsearch**: Needs 2-4GB RAM minimum
- **Logstash**: Needs 1-2GB RAM
- **Kibana**: Needs 1GB RAM
- **Total**: ~4-7GB RAM just for logging!

This caused TLS handshake timeouts because minikube ran out of resources.

## Solution Options (Choose One)

### Option 1: Lightweight ELK in Kubernetes (Recommended)
- Use minimal resource limits
- Deploy only when needed
- Use lightweight alternatives

### Option 2: Fluentd + Elasticsearch (Lighter)
- Replace Logstash with Fluentd (uses less memory)
- Keep Elasticsearch and Kibana

### Option 3: External Managed Service
- Use Elastic Cloud (free tier available)
- No local resources needed

### Option 4: Minimal Logging (Lightest)
- Use Fluent Bit (very lightweight)
- Send to external service or simple storage

---

## Step-by-Step: Option 1 - Lightweight ELK in Kubernetes

### Step 1: Create Resource-Limited Elasticsearch

**File**: `k8s/elasticsearch-deployment.yaml`

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: elasticsearch
  namespace: disease-detector
spec:
  replicas: 1
  selector:
    matchLabels:
      app: elasticsearch
  template:
    metadata:
      labels:
        app: elasticsearch
    spec:
      containers:
      - name: elasticsearch
        image: docker.elastic.co/elasticsearch/elasticsearch:8.11.0
        env:
        - name: discovery.type
          value: "single-node"
        - name: xpack.security.enabled
          value: "false"
        - name: ES_JAVA_OPTS
          value: "-Xms256m -Xmx512m"  # Minimal memory
        resources:
          requests:
            memory: "512Mi"
            cpu: "250m"
          limits:
            memory: "1Gi"  # Strict limit
            cpu: "500m"
        ports:
        - containerPort: 9200
---
apiVersion: v1
kind: Service
metadata:
  name: elasticsearch
  namespace: disease-detector
spec:
  selector:
    app: elasticsearch
  ports:
  - port: 9200
    targetPort: 9200
  type: ClusterIP
```

**What to do:**
1. Create this file in `k8s/elasticsearch-deployment.yaml`
2. This limits Elasticsearch to 1GB RAM max (vs 2-4GB default)

---

### Step 2: Create Lightweight Fluentd (Replace Logstash)

**File**: `k8s/fluentd-daemonset.yaml`

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: fluentd-config
  namespace: disease-detector
data:
  fluent.conf: |
    <source>
      @type tail
      path /var/log/app/*.log
      pos_file /var/log/fluentd.log.pos
      tag disease-detector
      format json
      read_from_head true
    </source>
    
    <filter disease-detector>
      @type record_transformer
      <record>
        hostname ${hostname}
        timestamp ${time}
      </record>
    </filter>
    
    <match disease-detector>
      @type elasticsearch
      host elasticsearch.disease-detector.svc.cluster.local
      port 9200
      index_name disease-detector-logs
      type_name _doc
      logstash_format true
      logstash_dateformat %Y.%m.%d
      flush_interval 10s
    </match>
---
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: fluentd
  namespace: disease-detector
spec:
  selector:
    matchLabels:
      app: fluentd
  template:
    metadata:
      labels:
        app: fluentd
    spec:
      containers:
      - name: fluentd
        image: fluent/fluentd-kubernetes-daemonset:v1-debian-elasticsearch
        env:
        - name: FLUENT_ELASTICSEARCH_HOST
          value: "elasticsearch.disease-detector.svc.cluster.local"
        - name: FLUENT_ELASTICSEARCH_PORT
          value: "9200"
        resources:
          requests:
            memory: "128Mi"
            cpu: "100m"
          limits:
            memory: "256Mi"  # Very lightweight!
            cpu: "200m"
        volumeMounts:
        - name: app-logs
          mountPath: /var/log/app
          readOnly: true
        - name: fluentd-config
          mountPath: /fluentd/etc
      volumes:
      - name: app-logs
        hostPath:
          path: /var/log/app
      - name: fluentd-config
        configMap:
          name: fluentd-config
```

**What to do:**
1. Create this file in `k8s/fluentd-daemonset.yaml`
2. Fluentd uses ~256MB vs Logstash's 1-2GB

---

### Step 3: Create Lightweight Kibana

**File**: `k8s/kibana-deployment.yaml`

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: kibana
  namespace: disease-detector
spec:
  replicas: 1
  selector:
    matchLabels:
      app: kibana
  template:
    metadata:
      labels:
        app: kibana
    spec:
      containers:
      - name: kibana
        image: docker.elastic.co/kibana/kibana:8.11.0
        env:
        - name: ELASTICSEARCH_HOSTS
          value: "http://elasticsearch.disease-detector.svc.cluster.local:9200"
        resources:
          requests:
            memory: "512Mi"
            cpu: "250m"
          limits:
            memory: "1Gi"  # Strict limit
            cpu: "500m"
        ports:
        - containerPort: 5601
---
apiVersion: v1
kind: Service
metadata:
  name: kibana
  namespace: disease-detector
spec:
  selector:
    app: kibana
  ports:
  - port: 5601
    targetPort: 5601
  type: LoadBalancer  # Or NodePort for minikube
```

**What to do:**
1. Create this file in `k8s/kibana-deployment.yaml`
2. Limits Kibana to 1GB RAM

---

### Step 4: Update Backend Deployment to Share Logs

**What to do:**
1. Open `k8s/backend-deployment.yaml`
2. Add volume mount for logs:

```yaml
volumeMounts:
- name: app-logs
  mountPath: /app/logs
volumes:
- name: app-logs
  emptyDir: {}
```

3. Ensure your app writes logs to `/app/logs/` directory

---

### Step 5: Update Ansible Playbook

**What to do:**
1. Open `ansible/playbook.yaml`
2. Add a new task after applying services:

```yaml
- name: Deploy ELK Stack (optional, lightweight)
  shell: |
    {% if kubeconfig_path %}
    export KUBECONFIG={{ kubeconfig_path }}
    {% endif %}
    # Only deploy if elk_enabled is true
    {% if elk_enabled | default(false) %}
    kubectl apply -f {{ playbook_dir }}/../k8s/elasticsearch-deployment.yaml --validate=false
    kubectl apply -f {{ playbook_dir }}/../k8s/fluentd-daemonset.yaml --validate=false
    kubectl apply -f {{ playbook_dir }}/../k8s/kibana-deployment.yaml --validate=false
    {% endif %}
  when: elk_enabled | default(false)
```

---

### Step 6: Update Jenkinsfile (Optional Stage)

**What to do:**
1. Open `Jenkinsfile`
2. Add optional ELK deployment stage (after health check):

```groovy
stage('Deploy ELK Stack (Optional)') {
    when {
        expression { 
            return env.DEPLOY_ELK == 'true' 
        }
    }
    steps {
        withCredentials([file(credentialsId: 'kubeconfig', variable: 'KUBECONFIG_FILE')]) {
            sh '''
                export KUBECONFIG="$KUBECONFIG_FILE"
                kubectl apply -f k8s/elasticsearch-deployment.yaml --validate=false
                kubectl apply -f k8s/fluentd-daemonset.yaml --validate=false
                kubectl apply -f k8s/kibana-deployment.yaml --validate=false
            '''
        }
    }
}
```

---

### Step 7: Deploy and Verify

**Commands to run:**

```bash
# 1. Apply ELK stack
kubectl apply -f k8s/elasticsearch-deployment.yaml
kubectl apply -f k8s/fluentd-daemonset.yaml
kubectl apply -f k8s/kibana-deployment.yaml

# 2. Wait for pods to be ready
kubectl wait --for=condition=ready pod -l app=elasticsearch -n disease-detector --timeout=300s
kubectl wait --for=condition=ready pod -l app=kibana -n disease-detector --timeout=300s

# 3. Check resource usage
kubectl top pods -n disease-detector

# 4. Port forward to access Kibana
kubectl port-forward svc/kibana 5601:5601 -n disease-detector

# 5. Access Kibana
# Open: http://localhost:5601
```

---

## Alternative: Option 2 - External Elastic Cloud (No Local Resources)

### Step 1: Sign up for Elastic Cloud
1. Go to: https://cloud.elastic.co
2. Create free account (14-day trial, then free tier available)
3. Create deployment (choose smallest size)

### Step 2: Get Connection Details
1. Copy Elasticsearch endpoint URL
2. Copy API key or username/password

### Step 3: Update Backend to Send Logs Directly

**What to do:**
1. Update `app.py` to send logs directly to Elasticsearch
2. Use environment variables for Elasticsearch URL
3. No need for Logstash/Fluentd locally

---

## Resource Comparison

| Solution | RAM Usage | CPU Usage | Complexity |
|----------|-----------|-----------|------------|
| Full ELK (docker-compose) | 4-7GB | High | Medium |
| Lightweight ELK (K8s) | 1.5-2GB | Low | Medium |
| Fluentd + ES | 1-1.5GB | Low | Low |
| External Elastic Cloud | 0GB local | 0 local | Low |

---

## Recommendations

1. **For Development**: Use Option 2 (External Elastic Cloud) - zero local resources
2. **For Production**: Use Option 1 (Lightweight ELK in K8s) - controlled resources
3. **For Minimal Setup**: Skip ELK, use simple file logging or cloud logging

---

## Next Steps

1. Choose your option
2. Create the YAML files as shown above
3. Test with minimal resources first
4. Monitor resource usage: `kubectl top pods -n disease-detector`
5. Adjust resource limits if needed

Would you like me to help you implement a specific option?



