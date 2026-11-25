terraform {
  required_providers { google = { source = "hashicorp/google", version = ">= 5.30, < 7.0" } }
}
# One global HTTPS LB per customer-env, host-based routing to every Cloud Run / MIG product.
locals {
  hosts = { for p, b in var.backends : p => (var.env == "prod" ? "${p}.${var.domain}" : "${p}.${var.env}.${var.domain}") }
}
resource "google_compute_security_policy" "armor" {
  project = var.project_id
  name    = "${var.name}-armor"
  rule {
    action   = "allow"
    priority = 2147483647
    match {
      versioned_expr = "SRC_IPS_V1"
      config { src_ip_ranges = ["*"] }
    }
  }
  rule {
    action   = "deny(403)"
    priority = 1000
    match {
      expr { expression = "evaluatePreconfiguredWaf('sqli-v33-stable')" }
    }
  }
  rule {
    action   = "deny(403)"
    priority = 1001
    match {
      expr { expression = "evaluatePreconfiguredWaf('xss-v33-stable')" }
    }
  }
}
resource "google_compute_backend_service" "this" {
  for_each              = var.backends
  project               = var.project_id
  name                  = "${var.name}-${each.key}"
  protocol              = each.value.type == "cloudrun" ? "HTTPS" : "HTTP"
  port_name             = each.value.type == "mig" ? "http" : null
  load_balancing_scheme = "EXTERNAL_MANAGED"
  security_policy       = google_compute_security_policy.armor.id
  health_checks         = each.value.type == "mig" ? [each.value.health_check] : null
  backend {
    group           = each.value.group
    balancing_mode  = each.value.type == "mig" ? "UTILIZATION" : null
    capacity_scaler = 1.0
  }
  log_config {
    enable      = true
    sample_rate = 1.0
  }
}
resource "google_compute_url_map" "this" {
  project         = var.project_id
  name            = var.name
  default_service = values(google_compute_backend_service.this)[0].id
  dynamic "host_rule" {
    for_each = local.hosts
    content {
      hosts        = [host_rule.value]
      path_matcher = host_rule.key
    }
  }
  dynamic "path_matcher" {
    for_each = local.hosts
    content {
      name            = path_matcher.key
      default_service = google_compute_backend_service.this[path_matcher.key].id
    }
  }
}
resource "google_compute_managed_ssl_certificate" "this" {
  project = var.project_id
  name    = "${var.name}-cert"
  managed { domains = values(local.hosts) }
  lifecycle { create_before_destroy = true }
}
resource "google_compute_target_https_proxy" "this" {
  project          = var.project_id
  name             = var.name
  url_map          = google_compute_url_map.this.id
  ssl_certificates = [google_compute_managed_ssl_certificate.this.id]
}
resource "google_compute_global_address" "this" {
  project = var.project_id
  name    = var.name
}
resource "google_compute_global_forwarding_rule" "https" {
  project               = var.project_id
  name                  = var.name
  target                = google_compute_target_https_proxy.this.id
  ip_address            = google_compute_global_address.this.id
  port_range            = "443"
  load_balancing_scheme = "EXTERNAL_MANAGED"
}
