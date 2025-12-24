# Add Resource Quotas to Production Namespace

## Priority: HIGH | Infrastructure

## Problem

Production namespace has no ResourceQuota, unlike staging. This allows:
- Resource exhaustion attacks
- Noisy neighbor problems
- Uncontrolled cost escalation

Staging has quotas at `infra/terraform/environments/staging/main.tf:300-319` but production doesn't.

## Task

1. **Create ResourceQuota for production:**
   ```yaml
   # infra/k8s/production/resource-quota.yaml

   apiVersion: v1
   kind: ResourceQuota
   metadata:
     name: plue-quota
     namespace: plue
   spec:
     hard:
       # Compute resources
       requests.cpu: "20"
       requests.memory: "40Gi"
       limits.cpu: "40"
       limits.memory: "80Gi"

       # Storage
       requests.storage: "100Gi"
       persistentvolumeclaims: "20"

       # Object counts
       pods: "100"
       services: "20"
       secrets: "50"
       configmaps: "50"
       replicationcontrollers: "0"  # Discourage old-style controllers
   ```

2. **Create LimitRange for default limits:**
   ```yaml
   # infra/k8s/production/limit-range.yaml

   apiVersion: v1
   kind: LimitRange
   metadata:
     name: plue-limits
     namespace: plue
   spec:
     limits:
       - type: Container
         default:
           cpu: "500m"
           memory: "512Mi"
         defaultRequest:
           cpu: "100m"
           memory: "128Mi"
         min:
           cpu: "50m"
           memory: "64Mi"
         max:
           cpu: "4"
           memory: "8Gi"

       - type: PersistentVolumeClaim
         min:
           storage: "1Gi"
         max:
           storage: "50Gi"
   ```

3. **Add Terraform resource:**
   ```terraform
   # infra/terraform/environments/production/quotas.tf

   resource "kubernetes_resource_quota" "plue" {
     metadata {
       name      = "plue-quota"
       namespace = kubernetes_namespace.plue.metadata[0].name
     }

     spec {
       hard = {
         "requests.cpu"    = "20"
         "requests.memory" = "40Gi"
         "limits.cpu"      = "40"
         "limits.memory"   = "80Gi"
         "pods"            = "100"
         "services"        = "20"
       }
     }
   }

   resource "kubernetes_limit_range" "plue" {
     metadata {
       name      = "plue-limits"
       namespace = kubernetes_namespace.plue.metadata[0].name
     }

     spec {
       limit {
         type = "Container"

         default = {
           cpu    = "500m"
           memory = "512Mi"
         }

         default_request = {
           cpu    = "100m"
           memory = "128Mi"
         }

         min = {
           cpu    = "50m"
           memory = "64Mi"
         }

         max = {
           cpu    = "4"
           memory = "8Gi"
         }
       }
     }
   }
   ```

4. **Verify existing deployments have resource specs:**
   ```bash
   # Check all deployments have resource limits
   kubectl get deployments -n plue -o jsonpath='{range .items[*]}{.metadata.name}: {.spec.template.spec.containers[0].resources}{"\n"}{end}'
   ```

5. **Update any deployments missing resources:**
   ```yaml
   # Ensure all containers have resources defined
   resources:
     requests:
       cpu: "100m"
       memory: "256Mi"
     limits:
       cpu: "1"
       memory: "1Gi"
   ```

6. **Add monitoring for quota usage:**
   ```yaml
   # Prometheus alert for quota approaching limit
   apiVersion: monitoring.coreos.com/v1
   kind: PrometheusRule
   metadata:
     name: quota-alerts
   spec:
     groups:
       - name: quota
         rules:
           - alert: ResourceQuotaAlmostFull
             expr: |
               kube_resourcequota{resource=~"requests.cpu|requests.memory", type="used"}
               /
               kube_resourcequota{resource=~"requests.cpu|requests.memory", type="hard"}
               > 0.8
             for: 5m
             labels:
               severity: warning
             annotations:
               summary: "Resource quota {{ $labels.resource }} is 80% used"
   ```

7. **Document quota values:**
   - Explain why these values were chosen
   - Document process for requesting quota increase
   - Link to cost implications

## Acceptance Criteria

- [ ] ResourceQuota applied to production namespace
- [ ] LimitRange provides sensible defaults
- [ ] All existing pods have resource limits
- [ ] Monitoring alerts configured
- [ ] Values aligned with expected workload
- [ ] Documentation updated
