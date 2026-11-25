terraform {
  required_providers { google = { source = "hashicorp/google", version = ">= 5.30, < 7.0" } }
}
resource "google_cloud_run_v2_service" "this" {
  for_each            = var.products
  project             = var.project_id
  name                = each.key
  location            = var.region
  ingress             = "INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER"
  deletion_protection = var.deletion_protection
  labels              = merge(var.labels, { product = each.key, version = replace(each.value.version, ".", "-") })

  template {
    service_account = each.value.service_account
    scaling {
      min_instance_count = var.min_instances
      max_instance_count = var.max_instances
    }
    vpc_access {
      egress = "PRIVATE_RANGES_ONLY"
      network_interfaces {
        network    = var.network
        subnetwork = var.subnetwork
      }
    }
    containers {
      image = "${var.registry}/${each.key}:${each.value.version}"
      resources {
        limits = { cpu = var.cpu, memory = var.memory }
      }
      dynamic "env" {
        for_each = merge(each.value.config, { PRODUCT_VERSION = each.value.version, CUSTOMER = var.customer, ENV = var.env })
        content {
          name  = env.key
          value = env.value
        }
      }
    }
  }
  traffic {
    type    = "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST"
    percent = 100
  }
}
# Ingress is LB-only; the LB is the public entry, so invoker is open at IAM level (app/IAP does authn).
resource "google_cloud_run_v2_service_iam_member" "invoker" {
  for_each = var.public_invoker ? var.products : {}
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.this[each.key].name
  role     = "roles/run.invoker"
  member   = "allUsers"
}
resource "google_compute_region_network_endpoint_group" "neg" {
  for_each              = var.products
  project               = var.project_id
  name                  = "${each.key}-neg"
  region                = var.region
  network_endpoint_type = "SERVERLESS"
  cloud_run { service = google_cloud_run_v2_service.this[each.key].name }
}
