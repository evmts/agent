# Restrict GKE Master Authorized Networks

## Priority: CRITICAL | Security

## Problem

GKE master (Kubernetes API server) is accessible from any IP address:

`infra/terraform/modules/gke/variables.tf:57-62`
```terraform
default = [
  {
    cidr_block   = "0.0.0.0/0"
    display_name = "All (use with caution)"
  }
]
```

This exposes the control plane to brute force attacks and vulnerability exploitation.

## Task

1. **Identify allowed access sources:**
   - Office/home IP ranges for developers
   - CI/CD pipeline IP ranges (GitHub Actions, etc.)
   - Cloud Shell CIDR (if used)
   - VPN endpoint IPs

2. **Update Terraform variables:**

   `infra/terraform/modules/gke/variables.tf`:
   ```terraform
   variable "master_authorized_networks" {
     description = "CIDR blocks authorized to access the GKE master. NEVER use 0.0.0.0/0 in production."
     type = list(object({
       cidr_block   = string
       display_name = string
     }))
     default = []  # Force explicit configuration

     validation {
       condition = alltrue([
         for network in var.master_authorized_networks :
         network.cidr_block != "0.0.0.0/0"
       ])
       error_message = "0.0.0.0/0 is not allowed for master authorized networks."
     }
   }
   ```

3. **Update production environment:**

   `infra/terraform/environments/production/main.tf`:
   ```terraform
   master_authorized_networks = [
     {
       cidr_block   = "203.0.113.0/24"  # Office IP range
       display_name = "Office Network"
     },
     {
       cidr_block   = "35.235.240.0/20"  # Cloud Shell
       display_name = "Google Cloud Shell"
     },
     # Add VPN, CI/CD as needed
   ]
   ```

4. **Consider Cloud IAP for kubectl:**
   - Enable IAP TCP forwarding
   - Configure `gcloud compute ssh` tunneling
   - Document access procedure

5. **Add monitoring:**
   - Alert on failed API server authentication
   - Log all kubectl access with user identity
   - Set up anomaly detection for unusual access patterns

6. **Update documentation:**
   - Document how to access cluster
   - Document process for adding new authorized networks
   - Add security policy for network changes

7. **Test changes:**
   - Verify authorized IPs can access
   - Verify unauthorized IPs are rejected
   - Test failover access method (Cloud Shell)

## Acceptance Criteria

- [ ] No `0.0.0.0/0` in any environment
- [ ] Terraform validation prevents overly permissive networks
- [ ] All developers can still access cluster
- [ ] CI/CD pipelines still work
- [ ] Documentation updated
- [ ] Access monitoring in place
