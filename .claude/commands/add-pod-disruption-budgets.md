# Add Pod Disruption Budgets

## Priority: MEDIUM | Reliability

## Problem

No PodDisruptionBudgets are defined for critical services. During node upgrades or voluntary disruptions, all pods could be terminated simultaneously, causing downtime.

## Task

1. **Create PDB for API service:**
   ```yaml
   # infra/k8s/production/pdb-api.yaml

   apiVersion: policy/v1
   kind: PodDisruptionBudget
   metadata:
     name: api-pdb
     namespace: plue
   spec:
     minAvailable: 1
     selector:
       matchLabels:
         app: api
   ---
   # Or use maxUnavailable for larger deployments
   apiVersion: policy/v1
   kind: PodDisruptionBudget
   metadata:
     name: api-pdb-percentage
     namespace: plue
   spec:
     maxUnavailable: 25%
     selector:
       matchLabels:
         app: api
   ```

2. **Create PDB for web service:**
   ```yaml
   # infra/k8s/production/pdb-web.yaml

   apiVersion: policy/v1
   kind: PodDisruptionBudget
   metadata:
     name: web-pdb
     namespace: plue
   spec:
     minAvailable: 1
     selector:
       matchLabels:
         app: web
   ```

3. **Create PDB for runner pool:**
   ```yaml
   # infra/k8s/production/pdb-runners.yaml

   apiVersion: policy/v1
   kind: PodDisruptionBudget
   metadata:
     name: runner-pdb
     namespace: plue
   spec:
     minAvailable: 2  # Keep at least 2 warm runners
     selector:
       matchLabels:
         app: runner-standby
   ```

4. **Add Terraform resources:**
   ```terraform
   # infra/terraform/kubernetes/pdb.tf

   resource "kubernetes_pod_disruption_budget_v1" "api" {
     metadata {
       name      = "api-pdb"
       namespace = kubernetes_namespace.plue.metadata[0].name
     }

     spec {
       min_available = "1"

       selector {
         match_labels = {
           app = "api"
         }
       }
     }
   }

   resource "kubernetes_pod_disruption_budget_v1" "web" {
     metadata {
       name      = "web-pdb"
       namespace = kubernetes_namespace.plue.metadata[0].name
     }

     spec {
       min_available = "1"

       selector {
         match_labels = {
           app = "web"
         }
       }
     }
   }

   resource "kubernetes_pod_disruption_budget_v1" "runners" {
     metadata {
       name      = "runner-pdb"
       namespace = kubernetes_namespace.plue.metadata[0].name
     }

     spec {
       min_available = "2"

       selector {
         match_labels = {
           app = "runner-standby"
         }
       }
     }
   }
   ```

5. **Verify replica counts support PDB:**
   ```bash
   # Check current replica counts
   kubectl get deployments -n plue -o jsonpath='{range .items[*]}{.metadata.name}: {.spec.replicas}{"\n"}{end}'

   # Ensure replicas > minAvailable for each service
   # If api has 2 replicas and minAvailable=1, only 1 can be disrupted at a time
   ```

6. **Update Helm values:**
   ```yaml
   # infra/helm/plue/values.yaml

   api:
     replicaCount: 3  # Increase if needed
     pdb:
       enabled: true
       minAvailable: 1

   web:
     replicaCount: 2
     pdb:
       enabled: true
       minAvailable: 1

   runners:
     replicaCount: 5
     pdb:
       enabled: true
       minAvailable: 2
   ```

7. **Add Helm template:**
   ```yaml
   # infra/helm/plue/templates/pdb.yaml

   {{- if .Values.api.pdb.enabled }}
   apiVersion: policy/v1
   kind: PodDisruptionBudget
   metadata:
     name: {{ include "plue.fullname" . }}-api
   spec:
     minAvailable: {{ .Values.api.pdb.minAvailable }}
     selector:
       matchLabels:
         app: api
   {{- end }}
   ```

8. **Test PDB behavior:**
   ```bash
   # Simulate node drain
   kubectl drain node-1 --ignore-daemonsets --delete-emptydir-data

   # Verify at least minAvailable pods remain running
   kubectl get pods -n plue -l app=api

   # Check PDB status
   kubectl get pdb -n plue
   ```

## Acceptance Criteria

- [ ] PDBs created for all critical services
- [ ] minAvailable set appropriately for each service
- [ ] Replica counts support the PDB constraints
- [ ] Node drain tested without full service disruption
- [ ] Terraform/Helm updated
- [ ] Documentation updated
