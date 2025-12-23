# Workflow Runner Sandbox Configuration

This document specifies the security configuration for workflow runner pods.

## Overview

All workflow and agent execution happens in sandboxed Kubernetes pods with the following isolation layers:

1. **gVisor Runtime** - Syscall interception and filtering
2. **Pod Security** - Read-only rootfs, non-root user, no privilege escalation
3. **Network Policy** - Egress allowlist only
4. **Resource Limits** - CPU, memory, and disk quotas

## gVisor Runtime Configuration

### Runtime Class

All runner pods must use the `gvisor` runtime class:

```yaml
runtimeClassName: gvisor
```

### What gVisor Provides

- **Syscall Filtering**: Intercepts all syscalls in userspace before reaching host kernel
- **Namespace Isolation**: Emulates Linux kernel interfaces in userspace
- **Attack Surface Reduction**: Reduces kernel attack surface by 90%+
- **Performance**: ~10-20% overhead compared to native containers

### Verification

Check that gVisor is active in a running pod:

```bash
kubectl exec -it <pod-name> -- dmesg | grep gVisor
# Should show: gVisor version X.Y.Z
```

## Pod Security Configuration

### Security Context

```yaml
securityContext:
  # Pod-level security
  runAsNonRoot: true
  runAsUser: 1000
  runAsGroup: 1000
  fsGroup: 1000
  seccompProfile:
    type: RuntimeDefault

  # Container-level security
  containers:
  - name: runner
    securityContext:
      allowPrivilegeEscalation: false
      readOnlyRootFilesystem: true
      capabilities:
        drop: ["ALL"]
```

### Explanation

| Setting | Purpose |
|---------|---------|
| `runAsNonRoot: true` | Prevents running as root user (UID 0) |
| `runAsUser: 1000` | Runs as unprivileged user |
| `readOnlyRootFilesystem: true` | Makes / read-only (only /workspace and /tmp writable) |
| `allowPrivilegeEscalation: false` | Prevents setuid/setgid binaries |
| `capabilities: drop: ["ALL"]` | Removes all Linux capabilities |
| `seccompProfile: RuntimeDefault` | Uses Docker's default seccomp filter |

### Writable Volumes

Only these paths are writable:

```yaml
volumeMounts:
- name: workspace
  mountPath: /workspace
- name: tmp
  mountPath: /tmp

volumes:
- name: workspace
  emptyDir:
    sizeLimit: 10Gi
- name: tmp
  emptyDir:
    sizeLimit: 1Gi
```

## Resource Limits

### CPU and Memory

```yaml
resources:
  requests:
    cpu: "500m"        # 0.5 CPU cores
    memory: "1Gi"      # 1 GiB RAM
  limits:
    cpu: "2"           # Max 2 CPU cores
    memory: "4Gi"      # Max 4 GiB RAM
    ephemeral-storage: "10Gi"  # Max 10 GiB disk
```

### Timeout

```yaml
activeDeadlineSeconds: 3600  # 1 hour max per workflow run
```

### Rationale

- **CPU**: Most workflows are I/O bound, 500m request is sufficient for heartbeat/idle
- **Memory**: 1Gi request handles typical workflows, 4Gi limit prevents OOM on host
- **Storage**: 10Gi ephemeral storage sufficient for most builds and caches
- **Timeout**: 1 hour is generous for most workflows, prevents infinite loops

## Network Policy

### Default Deny + Allowlist

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: runner-network-policy
  namespace: workflows
spec:
  podSelector:
    matchLabels:
      app: workflow-runner
  policyTypes:
  - Ingress
  - Egress

  # No ingress (runners never receive inbound connections)
  ingress: []

  egress:
  # Allow DNS resolution
  - to:
    - namespaceSelector: {}
      podSelector:
        matchLabels:
          k8s-app: kube-dns
    ports:
    - port: 53
      protocol: UDP

  # Allow Claude API
  - to:
    - podSelector: {}
    ports:
    - port: 443
      protocol: TCP

  # Allow Plue API callback (for streaming events)
  - to:
    - namespaceSelector:
        matchLabels:
          name: plue-system
      podSelector:
        matchLabels:
          app: plue-api
    ports:
    - port: 4000
      protocol: TCP
```

### Allowed Egress

1. **DNS (port 53/UDP)**: Required for domain name resolution
2. **HTTPS (port 443/TCP)**: For Claude API calls and web tool usage
3. **Plue API (port 4000/TCP)**: For streaming events back to server

### Blocked

- **Kubernetes API**: Cannot reach kube-apiserver
- **Metadata API**: Cannot reach cloud provider metadata endpoints
- **Internal Services**: Cannot reach other services in cluster
- **Other Pods**: Cannot reach other workflow runners

## Node Affinity

### Separate Node Pool

Runners should run on dedicated nodes with gVisor enabled:

```yaml
affinity:
  nodeAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
      nodeSelectorTerms:
      - matchExpressions:
        - key: workload-type
          operator: In
          values:
          - workflow-runner
```

### Taints and Tolerations

```yaml
# Node taint
taints:
- key: "sandbox.gke.io/runtime"
  value: "gvisor"
  effect: "NoSchedule"

# Pod toleration
tolerations:
- key: "sandbox.gke.io/runtime"
  operator: "Equal"
  value: "gvisor"
  effect: "NoSchedule"
```

## Service Account

### Minimal Permissions

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: workflow-runner
  namespace: workflows
automountServiceAccountToken: false  # Do not mount SA token
```

Runners do NOT need:
- Kubernetes API access
- Service account tokens
- Any RBAC permissions

## Complete Pod Spec Example

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: workflow-run-12345
  namespace: workflows
  labels:
    app: workflow-runner
    run-id: "12345"
spec:
  runtimeClassName: gvisor
  restartPolicy: Never
  activeDeadlineSeconds: 3600

  serviceAccountName: workflow-runner
  automountServiceAccountToken: false

  securityContext:
    runAsNonRoot: true
    runAsUser: 1000
    runAsGroup: 1000
    fsGroup: 1000
    seccompProfile:
      type: RuntimeDefault

  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        nodeSelectorTerms:
        - matchExpressions:
          - key: workload-type
            operator: In
            values:
            - workflow-runner

  tolerations:
  - key: "sandbox.gke.io/runtime"
    operator: "Equal"
    value: "gvisor"
    effect: "NoSchedule"

  containers:
  - name: runner
    image: gcr.io/plue-prod/runner:latest

    securityContext:
      allowPrivilegeEscalation: false
      readOnlyRootFilesystem: true
      capabilities:
        drop: ["ALL"]

    env:
    - name: TASK_ID
      value: "12345"
    - name: CALLBACK_URL
      value: "https://api.plue.dev/internal/tasks/12345/stream"
    - name: ANTHROPIC_API_KEY
      valueFrom:
        secretKeyRef:
          name: workflow-secrets
          key: anthropic-api-key

    resources:
      requests:
        cpu: "500m"
        memory: "1Gi"
      limits:
        cpu: "2"
        memory: "4Gi"
        ephemeral-storage: "10Gi"

    volumeMounts:
    - name: workspace
      mountPath: /workspace
    - name: tmp
      mountPath: /tmp

  volumes:
  - name: workspace
    emptyDir:
      sizeLimit: 10Gi
  - name: tmp
    emptyDir:
      sizeLimit: 1Gi
```

## Security Checklist

Before deploying runners, verify:

- [ ] gVisor runtime class exists and is configured on target nodes
- [ ] Node pool has `workload-type=workflow-runner` label
- [ ] Node pool has gVisor taint
- [ ] NetworkPolicy is applied to workflows namespace
- [ ] Service account has `automountServiceAccountToken: false`
- [ ] Pod security context includes all required settings
- [ ] Resource limits are configured
- [ ] activeDeadlineSeconds is set
- [ ] Writable volumes use emptyDir with size limits
- [ ] Secrets are mounted as environment variables (not files)

## Monitoring and Alerts

### Metrics to Track

- **Runner Escapes**: Monitor for any privilege escalations (should be zero)
- **Resource Exhaustion**: Track CPU/memory/disk usage per pod
- **Network Violations**: Alert on any blocked egress attempts
- **gVisor Performance**: Monitor syscall latency overhead

### Audit Logs

Enable Kubernetes audit logging for:
- Pod creation in workflows namespace
- SecurityContext changes
- NetworkPolicy changes
- Secret access

## References

- [gVisor Documentation](https://gvisor.dev/docs/)
- [Kubernetes Pod Security Standards](https://kubernetes.io/docs/concepts/security/pod-security-standards/)
- [NetworkPolicy Best Practices](https://kubernetes.io/docs/concepts/services-networking/network-policies/)
- [GKE Sandbox Documentation](https://cloud.google.com/kubernetes-engine/docs/how-to/sandbox-pods)
