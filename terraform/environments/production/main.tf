# =============================================================================
# Plue Production Environment
# =============================================================================
# Root module that composes all infrastructure for Plue deployment.
#
# Deploy order:
# 1. terraform init
# 2. terraform apply -target=module.project
# 3. terraform apply -target=module.networking
# 4. terraform apply -target=module.cloudsql
# 5. terraform apply -target=module.gke -target=module.secrets -target=module.artifact_registry
# 6. Build and push Docker images to Artifact Registry
# 7. Add ANTHROPIC_API_KEY to Secret Manager manually
# 8. terraform apply (full)
# 9. terraform apply -target=module.dns (after LB IP is available)

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.25"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.10"
    }
  }
}

# -----------------------------------------------------------------------------
# Providers
# -----------------------------------------------------------------------------

provider "google" {
  project = var.project_id
  region  = var.region
}

provider "google-beta" {
  project = var.project_id
  region  = var.region
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

# Kubernetes provider configured after GKE is created
provider "kubernetes" {
  host                   = "https://${module.gke.cluster_endpoint}"
  token                  = data.google_client_config.default.access_token
  cluster_ca_certificate = base64decode(module.gke.cluster_ca_certificate)
}

provider "helm" {
  kubernetes {
    host                   = "https://${module.gke.cluster_endpoint}"
    token                  = data.google_client_config.default.access_token
    cluster_ca_certificate = base64decode(module.gke.cluster_ca_certificate)
  }
}

data "google_client_config" "default" {}

# -----------------------------------------------------------------------------
# Locals
# -----------------------------------------------------------------------------

locals {
  name_prefix = "plue"
  labels = {
    app         = "plue"
    environment = "production"
    managed-by  = "terraform"
  }

  # Compute schema hash for migration job naming
  schema_hash = substr(sha256(file("${path.module}/../../../db/schema.sql")), 0, 8)
}

# -----------------------------------------------------------------------------
# Module: Project
# -----------------------------------------------------------------------------

module "project" {
  source = "../../modules/project"

  project_name    = var.project_name
  project_id      = var.project_id
  org_id          = var.org_id
  billing_account = var.billing_account
  labels          = local.labels
}

# -----------------------------------------------------------------------------
# Module: Networking
# -----------------------------------------------------------------------------

module "networking" {
  source = "../../modules/networking"

  name_prefix     = local.name_prefix
  project_id      = module.project.project_id
  region          = var.region
  gke_subnet_cidr = var.gke_subnet_cidr
  pods_cidr       = var.pods_cidr
  services_cidr   = var.services_cidr

  depends_on = [module.project]
}

# -----------------------------------------------------------------------------
# Module: Cloud SQL
# -----------------------------------------------------------------------------

module "cloudsql" {
  source = "../../modules/cloudsql"

  name_prefix            = local.name_prefix
  project_id             = module.project.project_id
  region                 = var.region
  vpc_id                 = module.networking.vpc_id
  private_vpc_connection = module.networking.private_vpc_connection
  tier                   = var.db_tier
  disk_size_gb           = var.db_disk_size_gb
  ha_enabled             = var.db_ha_enabled
  deletion_protection    = var.deletion_protection
  labels                 = local.labels

  depends_on = [module.networking]
}

# -----------------------------------------------------------------------------
# Module: GKE
# -----------------------------------------------------------------------------

module "gke" {
  source = "../../modules/gke"

  name_prefix                   = local.name_prefix
  project_id                    = module.project.project_id
  region                        = var.region
  node_zones                    = var.gke_node_zones
  vpc_id                        = module.networking.vpc_id
  subnet_id                     = module.networking.gke_subnet_id
  pods_secondary_range_name     = module.networking.pods_secondary_range_name
  services_secondary_range_name = module.networking.services_secondary_range_name
  primary_machine_type          = var.gke_machine_type
  primary_pool_min_size         = var.gke_min_nodes
  primary_pool_max_size         = var.gke_max_nodes
  deletion_protection           = var.deletion_protection
  labels                        = local.labels

  depends_on = [module.networking]
}

# -----------------------------------------------------------------------------
# Module: Artifact Registry
# -----------------------------------------------------------------------------

module "artifact_registry" {
  source = "../../modules/artifact-registry"

  name_prefix       = local.name_prefix
  project_id        = module.project.project_id
  project_number    = module.project.project_number
  region            = var.region
  gke_node_sa_email = module.gke.node_service_account_email
  labels            = local.labels

  depends_on = [module.gke]
}

# -----------------------------------------------------------------------------
# Module: Secrets
# -----------------------------------------------------------------------------

module "secrets" {
  source = "../../modules/secrets"

  name_prefix            = local.name_prefix
  project_id             = module.project.project_id
  database_url_secret_id = module.cloudsql.database_url_secret_id
  k8s_namespace          = "plue"
  k8s_service_account    = "plue-workload"
  labels                 = local.labels

  depends_on = [module.cloudsql]
}

# -----------------------------------------------------------------------------
# Module: Kubernetes Resources
# -----------------------------------------------------------------------------

module "kubernetes" {
  source = "../../kubernetes"

  project_id                  = module.project.project_id
  namespace                   = "plue"
  workload_sa_email           = module.secrets.workload_service_account_email
  database_url_secret_name    = module.cloudsql.database_url_secret_name
  anthropic_api_key_secret_id = module.secrets.anthropic_api_key_secret_id
  session_secret_secret_id    = module.secrets.session_secret_secret_id
  registry_url                = module.artifact_registry.repository_url
  image_tag                   = var.image_tag
  domain                      = var.domain
  api_replicas                = var.api_replicas
  electric_storage_size       = var.electric_storage_size
  repos_storage_size          = var.repos_storage_size

  # Cloudflare Tunnel configuration (for edge deployment)
  enable_cloudflare_tunnel  = var.enable_edge
  cloudflare_tunnel_token   = var.enable_edge ? module.cloudflare_tunnel[0].tunnel_token : ""
  enable_external_lb        = !var.enable_edge  # Disable external LB when edge is enabled

  # Pass through for services
  providers = {
    kubernetes = kubernetes
    helm       = helm
  }

  depends_on = [module.gke, module.secrets, module.artifact_registry]
}

# -----------------------------------------------------------------------------
# Module: DNS (Cloudflare)
# -----------------------------------------------------------------------------

module "dns" {
  source = "../../modules/dns"

  cloudflare_zone_id = var.cloudflare_zone_id
  domain             = var.domain
  subdomain          = var.subdomain
  # When edge is enabled, DNS points to Workers, not LB
  load_balancer_ip   = var.enable_edge ? "0.0.0.0" : module.kubernetes.load_balancer_ip
  enable_proxy       = true
  enable_adminer_dns = !var.enable_edge # Disable adminer when edge is enabled

  depends_on = [module.kubernetes]
}

# -----------------------------------------------------------------------------
# Module: Cloudflare Tunnel (connects Workers to private GKE)
# -----------------------------------------------------------------------------

module "cloudflare_tunnel" {
  source = "../../modules/cloudflare-tunnel"
  count  = var.enable_edge ? 1 : 0

  account_id    = var.cloudflare_account_id
  tunnel_name   = "${local.name_prefix}-origin-tunnel"
  tunnel_secret = random_password.tunnel_secret[0].result

  # Internal service URLs (resolved within GKE cluster)
  origin_web_service     = "http://web:5173"
  origin_api_service     = "http://api:4000"
  origin_electric_service = "http://electric:3000"
}

# Random secret for tunnel authentication
resource "random_password" "tunnel_secret" {
  count   = var.enable_edge ? 1 : 0
  length  = 64
  special = false
}

# Random secret for JWT signing
resource "random_password" "jwt_secret" {
  count   = var.enable_edge ? 1 : 0
  length  = 64
  special = false
}

# -----------------------------------------------------------------------------
# Module: Cloudflare Workers (edge rendering)
# -----------------------------------------------------------------------------

module "cloudflare_workers" {
  source = "../../modules/cloudflare-workers"
  count  = var.enable_edge ? 1 : 0

  account_id  = var.cloudflare_account_id
  zone_id     = var.cloudflare_zone_id
  domain      = var.domain
  environment = "production"

  # Internal hostnames (resolved via Cloudflare Tunnel)
  origin_host  = "origin.internal"
  electric_url = "http://electric.internal:3000"

  jwt_secret = random_password.jwt_secret[0].result

  depends_on = [module.cloudflare_tunnel]
}
