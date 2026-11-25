variable "catalog_path" {
  type    = string
  default = "../../../catalog/customers.yaml"
}
variable "prefix" {
  description = "Project id prefix (keep short: project ids max 30 chars)"
  type        = string
  default     = "pl"
}
variable "billing_account" { type = string }
# ---- outputs of live/platform ----
variable "customers_folder_id" { type = string }
variable "host_project_id" { type = string }
variable "shared_project_id" { type = string }
variable "network_id" { type = string }
variable "network_self_link" { type = string }
variable "subnets" { type = map(string) }
variable "registry" { type = string }
variable "registry_repository_project" { type = string }
variable "registry_location" {
  type    = string
  default = "us-central1"
}
variable "gke_node_supernet" {
  type    = string
  default = "10.64.0.0/12"
}
variable "gke_pods_supernet" {
  type    = string
  default = "100.64.0.0/10"
}
variable "gke_services_supernet" {
  type    = string
  default = "10.128.0.0/12"
}
