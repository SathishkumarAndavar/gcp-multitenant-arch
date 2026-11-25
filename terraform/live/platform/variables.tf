variable "org_id" { type = string }
variable "billing_account" { type = string }
variable "prefix" {
  type    = string
  default = "acme-plat"
}
variable "default_region" {
  type    = string
  default = "us-central1"
}
variable "regions" {
  description = "Regions where customers may be placed"
  type        = list(string)
  default     = ["us-central1", "europe-west1"]
}
variable "envs" {
  type    = list(string)
  default = ["dev", "stage", "uat", "prod"]
}
variable "github_org" {
  description = "GitHub org allowed to deploy via OIDC"
  type        = string
}

variable "github_repo" {
  type        = string
  description = "Infra repository allowed to impersonate the deployer (OIDC attribute.repository)."
}
