terraform {
  required_version = ">= 1.5"
  required_providers { google = { source = "hashicorp/google", version = ">= 5.30, < 7.0" } }
  # backend "gcs" { bucket = "<tfstate-bucket>" prefix = "platform" }   # configure via -backend-config
}
provider "google" { region = var.default_region }
