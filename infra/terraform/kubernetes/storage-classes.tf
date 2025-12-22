# =============================================================================
# Storage Classes
# =============================================================================
# SSD storage classes for persistent volumes.

resource "kubernetes_storage_class" "ssd" {
  metadata {
    name = "ssd"

    labels = {
      managed-by = "terraform"
    }
  }

  storage_provisioner = "pd.csi.storage.gke.io"
  reclaim_policy      = "Delete"
  volume_binding_mode = "WaitForFirstConsumer"

  parameters = {
    type = "pd-ssd"
  }

  allow_volume_expansion = true
}

resource "kubernetes_storage_class" "ssd_retain" {
  metadata {
    name = "ssd-retain"

    labels = {
      managed-by = "terraform"
    }
  }

  storage_provisioner = "pd.csi.storage.gke.io"
  reclaim_policy      = "Retain"
  volume_binding_mode = "WaitForFirstConsumer"

  parameters = {
    type = "pd-ssd"
  }

  allow_volume_expansion = true
}
