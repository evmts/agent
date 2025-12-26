---
name: kubernetes
description: Kubernetes container orchestration platform. Use for K8s clusters, deployments, pods, services, networking, storage, configuration, and DevOps tasks.
---

# Kubernetes Skill

Comprehensive assistance with Kubernetes development, operations, and troubleshooting, generated from official documentation.

## When to Use This Skill

This skill should be triggered when users:

### Working with Kubernetes Resources
- Creating, updating, or deleting Kubernetes resources (Pods, Deployments, Services, etc.)
- Writing or modifying YAML manifests
- Managing ConfigMaps, Secrets, or PersistentVolumes
- Working with StatefulSets, DaemonSets, or Jobs

### Using kubectl Commands
- Running kubectl commands or asking about kubectl syntax
- Querying cluster resources (`kubectl get`, `kubectl describe`)
- Debugging pods or containers (`kubectl logs`, `kubectl exec`)
- Applying or managing configurations (`kubectl apply`, `kubectl rollout`)

### Cluster Operations
- Setting up or configuring Kubernetes clusters
- Managing namespaces and RBAC (Role-Based Access Control)
- Troubleshooting cluster issues or resource problems
- Monitoring cluster health or resource usage

### Networking & Services
- Configuring Services (ClusterIP, NodePort, LoadBalancer)
- Setting up Ingress controllers or network policies
- Working with DNS resolution in Kubernetes
- Debugging network connectivity issues

### Storage & Configuration
- Configuring PersistentVolumes and PersistentVolumeClaims
- Working with StorageClasses
- Managing application configuration via ConfigMaps and Secrets
- Setting up encryption at rest

### Advanced Topics
- Implementing custom resource definitions (CRDs)
- Working with operators or controllers
- Setting up autoscaling (HPA, VPA)
- Implementing security policies and admission controllers

## Quick Reference

### Essential kubectl Commands

**Cluster Info & Context**
```shell
# View cluster information
kubectl cluster-info

# Get current context
kubectl config current-context

# Switch context
kubectl config use-context <context-name>

# Set default namespace
kubectl config set-context --current --namespace=<namespace-name>
```

**Resource Management**
```shell
# Apply configuration from file or directory
kubectl apply -f <file.yaml>
kubectl apply -f <directory>

# Create resource imperatively
kubectl create deployment nginx --image=nginx

# Delete resources
kubectl delete -f <file.yaml>
kubectl delete pod <pod-name>
kubectl delete pods,services -l <label-key>=<label-value>
```

**Viewing Resources**
```shell
# List resources
kubectl get pods
kubectl get pods -o wide
kubectl get all -n <namespace>
kubectl get pods --all-namespaces

# View multiple resource types
kubectl get pods,services,deployments

# Describe resource details
kubectl describe pod <pod-name>
kubectl describe node <node-name>

# Watch resources for changes
kubectl get pods --watch
```

**Output Formats**
```shell
# JSON output
kubectl get pod <pod-name> -o json

# YAML output
kubectl get pod <pod-name> -o yaml

# Custom columns
kubectl get pods -o custom-columns=NAME:.metadata.name,STATUS:.status.phase

# JSONPath
kubectl get pods -o jsonpath='{.items[*].metadata.name}'
```

**Filtering & Selection**
```shell
# Filter by label
kubectl get pods -l app=nginx
kubectl get pods -l 'env in (prod,staging)'

# Filter by field
kubectl get pods --field-selector=status.phase=Running
kubectl get pods --field-selector=spec.nodeName=<node-name>

# Sort output
kubectl get pods --sort-by=.metadata.creationTimestamp
```

**Debugging & Troubleshooting**
```shell
# View logs
kubectl logs <pod-name>
kubectl logs <pod-name> -c <container-name>
kubectl logs <pod-name> --follow
kubectl logs <pod-name> --previous

# Execute commands in container
kubectl exec <pod-name> -- <command>
kubectl exec -it <pod-name> -- /bin/bash
kubectl exec <pod-name> -c <container-name> -- <command>

# Port forwarding
kubectl port-forward <pod-name> <local-port>:<remote-port>
kubectl port-forward service/<service-name> <local-port>:<remote-port>

# Copy files
kubectl cp <pod-name>:/path/to/file /local/path
kubectl cp /local/path <pod-name>:/path/to/file
```

**Node Management**
```shell
# Mark node as unschedulable
kubectl cordon <node-name>

# Drain node for maintenance
kubectl drain <node-name> --ignore-daemonsets

# Mark node as schedulable
kubectl uncordon <node-name>

# View node resources
kubectl top nodes
kubectl top pods
```

**Deployments & Scaling**
```shell
# Create deployment
kubectl create deployment <name> --image=<image>

# Scale deployment
kubectl scale deployment <name> --replicas=<count>

# Autoscale deployment
kubectl autoscale deployment <name> --min=<min> --max=<max> --cpu-percent=<percent>

# Update image
kubectl set image deployment/<name> <container>=<new-image>

# View rollout status
kubectl rollout status deployment/<name>

# View rollout history
kubectl rollout history deployment/<name>

# Rollback deployment
kubectl rollout undo deployment/<name>
kubectl rollout undo deployment/<name> --to-revision=<revision>
```

**Services & Networking**
```shell
# Expose deployment as service
kubectl expose deployment <name> --port=<port> --target-port=<target-port>

# Create service
kubectl create service clusterip <name> --tcp=<port>:<target-port>

# View endpoints
kubectl get endpoints

# Test DNS resolution
kubectl run -it --rm debug --image=busybox --restart=Never -- nslookup <service-name>
```

**Configuration & Secrets**
```shell
# Create ConfigMap from literal
kubectl create configmap <name> --from-literal=<key>=<value>

# Create ConfigMap from file
kubectl create configmap <name> --from-file=<path>

# Create Secret
kubectl create secret generic <name> --from-literal=<key>=<value>
kubectl create secret tls <name> --cert=<cert-file> --key=<key-file>

# View Secret data (base64 encoded)
kubectl get secret <name> -o jsonpath='{.data}'
```

**Labels & Annotations**
```shell
# Add label
kubectl label pod <pod-name> <key>=<value>

# Remove label
kubectl label pod <pod-name> <key>-

# Update label
kubectl label pod <pod-name> <key>=<value> --overwrite

# Add annotation
kubectl annotate pod <pod-name> <key>=<value>
```

**Resource Quotas & Limits**
```shell
# View resource usage
kubectl describe resourcequota -n <namespace>
kubectl describe limitrange -n <namespace>

# View pod resource requests/limits
kubectl get pods -o custom-columns=NAME:.metadata.name,MEMORY:.spec.containers[*].resources.requests.memory,CPU:.spec.containers[*].resources.requests.cpu
```

**Advanced Operations**
```shell
# Edit resource
kubectl edit deployment <name>

# Patch resource
kubectl patch deployment <name> -p '{"spec":{"replicas":3}}'

# Replace resource
kubectl replace -f <file.yaml>

# Diff changes before applying
kubectl diff -f <file.yaml>

# Explain resource fields
kubectl explain pod
kubectl explain pod.spec.containers

# View API resources
kubectl api-resources
kubectl api-versions
```

## Common Use Cases

### 1. Deploying an Application

**Create Deployment:**
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-deployment
  labels:
    app: nginx
spec:
  replicas: 3
  selector:
    matchLabels:
      app: nginx
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
      - name: nginx
        image: nginx:1.21
        ports:
        - containerPort: 80
```

**Apply and verify:**
```shell
kubectl apply -f deployment.yaml
kubectl get deployments
kubectl get pods -l app=nginx
kubectl describe deployment nginx-deployment
```

### 2. Exposing an Application

**Create Service:**
```yaml
apiVersion: v1
kind: Service
metadata:
  name: nginx-service
spec:
  selector:
    app: nginx
  ports:
  - protocol: TCP
    port: 80
    targetPort: 80
  type: LoadBalancer
```

**Apply and test:**
```shell
kubectl apply -f service.yaml
kubectl get service nginx-service
kubectl describe service nginx-service
```

### 3. Debugging a Pod

```shell
# Check pod status
kubectl get pod <pod-name> -o wide

# View detailed information
kubectl describe pod <pod-name>

# Check logs
kubectl logs <pod-name>
kubectl logs <pod-name> --previous  # Previous container logs

# Get shell access
kubectl exec -it <pod-name> -- /bin/sh

# Check events
kubectl get events --sort-by=.metadata.creationTimestamp

# Check resource usage
kubectl top pod <pod-name>
```

### 4. Working with ConfigMaps and Secrets

**Create ConfigMap:**
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-config
data:
  database_url: "postgres://localhost:5432"
  log_level: "info"
```

**Use in Pod:**
```yaml
spec:
  containers:
  - name: app
    image: myapp:latest
    envFrom:
    - configMapRef:
        name: app-config
```

**Create and use Secret:**
```shell
# Create secret
kubectl create secret generic db-secret \
  --from-literal=username=admin \
  --from-literal=password=secret123

# Use in pod
env:
- name: DB_USER
  valueFrom:
    secretKeyRef:
      name: db-secret
      key: username
```

### 5. Setting Up Persistent Storage

**PersistentVolumeClaim:**
```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: app-pvc
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
  storageClassName: standard
```

**Use in Deployment:**
```yaml
spec:
  containers:
  - name: app
    volumeMounts:
    - name: data
      mountPath: /data
  volumes:
  - name: data
    persistentVolumeClaim:
      claimName: app-pvc
```

### 6. Implementing Health Checks

```yaml
spec:
  containers:
  - name: app
    image: myapp:latest
    livenessProbe:
      httpGet:
        path: /healthz
        port: 8080
      initialDelaySeconds: 30
      periodSeconds: 10
    readinessProbe:
      httpGet:
        path: /ready
        port: 8080
      initialDelaySeconds: 5
      periodSeconds: 5
```

### 7. Managing Updates with Rolling Updates

```shell
# Update image
kubectl set image deployment/nginx nginx=nginx:1.22

# Watch rollout
kubectl rollout status deployment/nginx

# Pause rollout
kubectl rollout pause deployment/nginx

# Resume rollout
kubectl rollout resume deployment/nginx

# Rollback if needed
kubectl rollout undo deployment/nginx
```

### 8. Working with Namespaces

```shell
# Create namespace
kubectl create namespace dev

# List all namespaces
kubectl get namespaces

# Set default namespace for context
kubectl config set-context --current --namespace=dev

# Delete namespace (careful!)
kubectl delete namespace dev

# Get resources across all namespaces
kubectl get pods --all-namespaces
```

### 9. DNS Resolution in Kubernetes

**Service DNS format:**
```
<service-name>.<namespace>.svc.cluster.local
```

**Example:**
```shell
# From within a pod in the same namespace
curl http://my-service

# From a different namespace
curl http://my-service.production.svc.cluster.local

# Test DNS resolution
kubectl run -it --rm debug --image=busybox --restart=Never -- nslookup my-service
```

### 10. Checking Connectivity

```shell
# Test port connectivity from within cluster
kubectl run -it --rm netcat --image=busybox --restart=Never -- nc -zv <service-name> <port>

# Test from specific pod
kubectl exec -it <pod-name> -- nc -zv <host> <port>

# Check if load balancer is accessible
nc -zv -w 2 <LOAD_BALANCER_IP> <PORT>
```

## Reference Files

This skill includes comprehensive documentation in `references/`:

- **api.md** - Complete API reference documentation
- **concepts.md** - Core Kubernetes concepts and architecture
- **configuration.md** - Configuration best practices
- **getting_started.md** - Getting started guides and tutorials
- **security.md** - Security policies and encryption
- **services.md** - Services, networking, and DNS
- **storage.md** - Storage classes and persistent volumes
- **workloads.md** - Deployments, StatefulSets, Jobs, and more
- **tasks.md** - Step-by-step task guides
- **tutorials.md** - End-to-end tutorials
- **other.md** - Additional resources and references

Use `Read` to access specific reference files when detailed information is needed.

## Working with This Skill

### For Beginners
Start with the **getting_started.md** or **tutorials.md** reference files for foundational concepts. Focus on:
- Understanding Pods, Deployments, and Services
- Basic kubectl commands
- YAML manifest structure

### For Specific Features
Use the appropriate category reference file:
- **api.md** - kubectl commands and API resources
- **workloads.md** - Deployments, Jobs, CronJobs
- **services.md** - Networking and service discovery
- **storage.md** - Persistent storage configuration
- **security.md** - RBAC, Secrets, and encryption

### For Operations & Troubleshooting
- Check **tasks.md** for step-by-step procedures
- Use **concepts.md** to understand underlying architecture
- Reference **configuration.md** for best practices

## Additional Resources

### Helper Scripts (`scripts/`)
Add automation scripts here for common tasks:
- Cluster health checks
- Resource cleanup utilities
- Deployment automation
- Backup and restore scripts

### Templates (`assets/`)
Store reusable templates:
- Deployment YAML templates
- Service definitions
- ConfigMap and Secret templates
- Ingress configurations
- NetworkPolicy examples

## Best Practices

### Manifest Organization
- Use declarative configurations (YAML files)
- Store manifests in version control
- Organize by namespace or application
- Use Kustomize or Helm for complex deployments

### Resource Management
- Always set resource requests and limits
- Use namespaces to organize resources
- Apply labels consistently for filtering
- Use annotations for metadata

### Security
- Follow principle of least privilege with RBAC
- Use Secrets for sensitive data
- Enable encryption at rest
- Implement NetworkPolicies
- Scan images for vulnerabilities

### High Availability
- Run multiple replicas for production apps
- Use PodDisruptionBudgets
- Configure liveness and readiness probes
- Implement proper health checks

### Monitoring & Logging
- Aggregate logs centrally
- Monitor resource usage
- Set up alerts for critical metrics
- Use kubectl top for quick checks

## Troubleshooting Guide

### Pod Issues

**Pod stuck in Pending:**
```shell
kubectl describe pod <pod-name>
# Check: Events, resource availability, PVC binding
```

**Pod in CrashLoopBackOff:**
```shell
kubectl logs <pod-name>
kubectl logs <pod-name> --previous
kubectl describe pod <pod-name>
# Check: Application errors, liveness probe failures
```

**ImagePullBackOff:**
```shell
kubectl describe pod <pod-name>
# Check: Image name, registry credentials, network access
```

### Service Issues

**Service not reachable:**
```shell
kubectl get endpoints <service-name>
kubectl describe service <service-name>
# Check: Selector labels match pods, endpoints exist
```

**DNS not resolving:**
```shell
kubectl get pods -n kube-system -l k8s-app=kube-dns
kubectl run -it --rm debug --image=busybox -- nslookup <service>
# Check: CoreDNS pods running, service exists
```

### Node Issues

**Node NotReady:**
```shell
kubectl describe node <node-name>
kubectl get pods -n kube-system
# Check: kubelet logs, network connectivity, resource pressure
```

## Version Information

This skill was automatically generated from official Kubernetes documentation and includes information accurate for Kubernetes 1.25+. While most concepts remain consistent across versions, always verify specific API versions and features for your cluster version:

```shell
kubectl version
kubectl api-versions
```

## Notes

- This skill was automatically generated from official documentation
- Reference files preserve the structure and examples from source docs
- Code examples include language detection for better syntax highlighting
- Quick reference patterns are extracted from common usage examples in the docs

## Updating

To refresh this skill with updated documentation:
1. Re-run the scraper with the same configuration
2. The skill will be rebuilt with the latest information
3. Verify all reference files are up to date
