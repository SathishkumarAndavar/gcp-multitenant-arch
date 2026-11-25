variable "project_id" { type = string }
variable "region" { type = string }
variable "customer" { type = string }
variable "env" { type = string }
variable "network" { type = string }
variable "subnetwork" { type = string }
variable "pods_range_name" { type = string }
variable "services_range_name" { type = string }
variable "registry" { type = string }
variable "products" {
  type = map(object({
    version         = string
    service_account = string
    config          = map(string)
  }))
}
variable "release_channel" {
  type    = string
  default = "REGULAR"
}
variable "authorized_cidrs" {
  type    = map(string)
  default = {}
}
variable "deletion_protection" {
  type    = bool
  default = false
}
variable "labels" {
  type    = map(string)
  default = {}
}
