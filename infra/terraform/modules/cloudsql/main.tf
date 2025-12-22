# =============================================================================
# Cloud SQL PostgreSQL Module
# =============================================================================
# Creates a PostgreSQL 16 instance with logical replication for ElectricSQL.

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

# -----------------------------------------------------------------------------
# Random Password for Database
# -----------------------------------------------------------------------------

resource "random_password" "db_password" {
  length  = 32
  special = false
}

# -----------------------------------------------------------------------------
# Cloud SQL PostgreSQL Instance
# -----------------------------------------------------------------------------

resource "google_sql_database_instance" "postgres" {
  name             = "${var.name_prefix}-postgres"
  project          = var.project_id
  region           = var.region
  database_version = "POSTGRES_16"

  depends_on = [var.private_vpc_connection]

  settings {
    tier              = var.tier
    availability_type = var.ha_enabled ? "REGIONAL" : "ZONAL"
    disk_size         = var.disk_size_gb
    disk_type         = "PD_SSD"
    disk_autoresize   = true

    # Private IP only (no public access)
    ip_configuration {
      ipv4_enabled                                  = false
      private_network                               = var.vpc_id
      enable_private_path_for_google_cloud_services = true
    }

    # Backup configuration
    backup_configuration {
      enabled                        = true
      point_in_time_recovery_enabled = true
      start_time                     = "03:00"
      transaction_log_retention_days = 7

      backup_retention_settings {
        retained_backups = var.backup_retention_days
        retention_unit   = "COUNT"
      }
    }

    # Database flags for ElectricSQL logical replication
    database_flags {
      name  = "cloudsql.logical_decoding"
      value = "on"
    }

    database_flags {
      name  = "max_replication_slots"
      value = "10"
    }

    database_flags {
      name  = "max_wal_senders"
      value = "10"
    }

    database_flags {
      name  = "wal_sender_timeout"
      value = "0"
    }

    # Query insights
    insights_config {
      query_insights_enabled  = true
      query_plans_per_minute  = 5
      query_string_length     = 1024
      record_application_tags = true
      record_client_address   = true
    }

    # Maintenance window (Sunday 4 AM)
    maintenance_window {
      day          = 7
      hour         = 4
      update_track = "stable"
    }

    user_labels = var.labels
  }

  deletion_protection = var.deletion_protection
}

# -----------------------------------------------------------------------------
# Database
# -----------------------------------------------------------------------------

resource "google_sql_database" "electric" {
  name     = "electric"
  project  = var.project_id
  instance = google_sql_database_instance.postgres.name
}

# -----------------------------------------------------------------------------
# Database User
# -----------------------------------------------------------------------------

resource "google_sql_user" "postgres" {
  name     = "postgres"
  project  = var.project_id
  instance = google_sql_database_instance.postgres.name
  password = random_password.db_password.result
}

# -----------------------------------------------------------------------------
# Store Password in Secret Manager
# -----------------------------------------------------------------------------

resource "google_secret_manager_secret" "db_password" {
  secret_id = "${var.name_prefix}-db-password"
  project   = var.project_id

  replication {
    auto {}
  }

  labels = var.labels
}

resource "google_secret_manager_secret_version" "db_password" {
  secret      = google_secret_manager_secret.db_password.id
  secret_data = random_password.db_password.result
}

# Store full connection string
resource "google_secret_manager_secret" "database_url" {
  secret_id = "${var.name_prefix}-database-url"
  project   = var.project_id

  replication {
    auto {}
  }

  labels = var.labels
}

resource "google_secret_manager_secret_version" "database_url" {
  secret      = google_secret_manager_secret.database_url.id
  secret_data = "postgresql://postgres:${random_password.db_password.result}@${google_sql_database_instance.postgres.private_ip_address}:5432/electric"
}
