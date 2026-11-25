terraform {
  required_providers { google = { source = "hashicorp/google", version = ">= 5.30, < 7.0" } }
}
# One regional Autopilot cluster per customer-env hosting all that customer's GKE products (namespace per product).
# Workloads themselves are deployed by Helm (helm/charts/product) from CI / Argo CD using `helm_values` output.
resource "google_container_cluster" "this" {
  project             = var.project_id
  name                = "${var.customer}-${var.env}"
  location            = var.region
  enable_autopilot    = true
  network             = var.network
  subnetwork          = var.subnetwork
  deletion_protection = var.deletion_protection
  release_channel { channel = var.release_channel }
  ip_allocation_policy {
    cluster_secondary_range_name  = var.pods_range_name
    services_secondary_range_name = var.services_range_name
  }
  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false
  }
  dynamic "master_authorized_networks_config" {
    for_each = length(var.authorized_cidrs) > 0 ? [1] : []
    content {
      dynamic "cidr_blocks" {
        for_each = var.authorized_cidrs
        content {
          cidr_block   = cidr_blocks.value
          display_name = cidr_blocks.key
        }
      }
    }
  }
  cluster_autoscaling {
    auto_provisioning_defaults {
      service_account = google_service_account.nodes.email
      oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]
    }
  }
  resource_labels = var.labels
  depends_on      = [google_project_iam_member.nodes]
}
resource "google_service_account" "nodes" {
  project      = var.project_id
  account_id   = "gke-nodes"
  display_name = "GKE node identity (${var.customer}-${var.env})"
}
resource "google_project_iam_member" "nodes" {
  for_each = toset(["roles/logging.logWriter", "roles/monitoring.metricWriter", "roles/monitoring.viewer", "roles/stackdriver.resourceMetadata.writer"])
  project  = var.project_id
  role     = each.value
  member   = "serviceAccount:${google_service_account.nodes.email}"
}
# Workload Identity: KSA <product>/<product> may impersonate the product GSA.
resource "google_service_account_iam_member" "wi" {
  for_each           = var.products
  service_account_id = "projects/${var.project_id}/serviceAccounts/${each.value.service_account}"
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[${each.key}/${each.key}]"
  depends_on         = [google_container_cluster.this]
}
