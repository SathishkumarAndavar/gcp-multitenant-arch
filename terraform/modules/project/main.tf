terraform {
  required_providers { google = { source = "hashicorp/google", version = ">= 5.30, < 7.0" } }
}
resource "google_project" "this" {
  name                = var.project_id
  project_id          = var.project_id
  folder_id           = var.folder_id
  billing_account     = var.billing_account
  auto_create_network = false
  labels              = var.labels
}
resource "google_project_service" "api" {
  for_each           = toset(var.apis)
  project            = google_project.this.project_id
  service            = each.value
  disable_on_destroy = false
}
# Attach as Shared VPC service project when a host project is given.
resource "google_compute_shared_vpc_service_project" "attach" {
  count           = var.host_project_id == "" ? 0 : 1
  host_project    = var.host_project_id
  service_project = google_project.this.project_id
  depends_on      = [google_project_service.api]
}
