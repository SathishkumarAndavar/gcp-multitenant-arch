variable "project_id" { type = string }
variable "region" { type = string }
variable "customer" { type = string }
variable "env" { type = string }
variable "registry" { type = string }
variable "network" { type = string }
variable "subnetwork" { type = string }
variable "products" {
  type = map(object({
    version         = string
    service_account = string
    config          = map(string)
  }))
}
variable "min_instances" {
  type    = number
  default = 0
}
variable "max_instances" {
  type    = number
  default = 10
}
variable "cpu" {
  type    = string
  default = "1"
}
variable "memory" {
  type    = string
  default = "512Mi"
}
variable "deletion_protection" {
  type    = bool
  default = false
}
variable "public_invoker" {
  type    = bool
  default = true
}
variable "labels" {
  type    = map(string)
  default = {}
}
