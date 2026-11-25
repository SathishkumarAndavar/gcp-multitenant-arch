terraform {
  required_providers { google = { source = "hashicorp/google", version = ">= 5.30, < 7.0" } }
}
# One least-privilege runtime identity per customer-env-product.
variable "project_id" { type = string }
variable "product" { type = string }
resource "google_service_account" "this" {
  project      = var.project_id
  account_id   = trimsuffix(substr("run-${var.product}", 0, 30), "-")
  display_name = "Runtime identity for ${var.product}"
}
output "email" { value = google_service_account.this.email }
output "member" { value = "serviceAccount:${google_service_account.this.email}" }
