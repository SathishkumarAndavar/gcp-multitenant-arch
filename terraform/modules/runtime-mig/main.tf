terraform {
  required_providers { google = { source = "hashicorp/google", version = ">= 5.30, < 7.0" } }
}
locals {
  canaries = { for k, v in var.products : k => v if v.canary != null }
}
resource "google_compute_instance_template" "stable" {
  for_each     = var.products
  project      = var.project_id
  name_prefix  = "${each.key}-${replace(each.value.version, ".", "-")}-"
  machine_type = var.machine_type
  region       = var.region
  tags         = ["app-${each.key}", "allow-lb-health"]
  labels       = merge(var.labels, { product = each.key })
  disk {
    source_image = "projects/${var.image_project}/global/images/${each.key}-${replace(each.value.version, ".", "-")}"
    boot         = true
    disk_type    = "pd-balanced"
  }
  network_interface { subnetwork = var.subnetwork } # no access_config => no external IP
  service_account {
    email  = each.value.service_account
    scopes = ["cloud-platform"]
  }
  shielded_instance_config {
    enable_secure_boot          = true
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }
  metadata = merge(each.value.config, { enable-oslogin = "TRUE", app-version = each.value.version, customer = var.customer })
  lifecycle { create_before_destroy = true }
}
resource "google_compute_instance_template" "canary" {
  for_each     = local.canaries
  project      = var.project_id
  name_prefix  = "${each.key}-${replace(each.value.canary.version, ".", "-")}-"
  machine_type = var.machine_type
  region       = var.region
  tags         = ["app-${each.key}", "allow-lb-health"]
  labels       = merge(var.labels, { product = each.key, track = "canary" })
  disk {
    source_image = "projects/${var.image_project}/global/images/${each.key}-${replace(each.value.canary.version, ".", "-")}"
    boot         = true
    disk_type    = "pd-balanced"
  }
  network_interface { subnetwork = var.subnetwork }
  service_account {
    email  = each.value.service_account
    scopes = ["cloud-platform"]
  }
  shielded_instance_config {
    enable_secure_boot = true
    enable_vtpm        = true
  }
  metadata = merge(each.value.config, { enable-oslogin = "TRUE", app-version = each.value.canary.version, customer = var.customer })
  lifecycle { create_before_destroy = true }
}
resource "google_compute_health_check" "this" {
  for_each = var.products
  project  = var.project_id
  name     = "${each.key}-hc"
  http_health_check {
    port         = 8080
    request_path = "/healthz"
  }
}
resource "google_compute_region_instance_group_manager" "this" {
  for_each           = var.products
  project            = var.project_id
  name               = each.key
  region             = var.region
  base_instance_name = each.key
  version {
    name              = "stable"
    instance_template = google_compute_instance_template.stable[each.key].self_link
  }
  dynamic "version" {
    for_each = each.value.canary != null ? [each.value.canary] : []
    content {
      name              = "canary"
      instance_template = google_compute_instance_template.canary[each.key].self_link
      target_size { percent = version.value.percent }
    }
  }
  named_port {
    name = "http"
    port = 8080
  }
  auto_healing_policies {
    health_check      = google_compute_health_check.this[each.key].id
    initial_delay_sec = 300
  }
  update_policy {
    type                  = "PROACTIVE"
    minimal_action        = "REPLACE"
    max_surge_fixed       = 3
    max_unavailable_fixed = 0
  }
}
resource "google_compute_region_autoscaler" "this" {
  for_each = var.products
  project  = var.project_id
  name     = "${each.key}-as"
  region   = var.region
  target   = google_compute_region_instance_group_manager.this[each.key].id
  autoscaling_policy {
    min_replicas    = var.min_replicas
    max_replicas    = var.max_replicas
    cooldown_period = 90
    cpu_utilization { target = 0.6 }
  }
}
