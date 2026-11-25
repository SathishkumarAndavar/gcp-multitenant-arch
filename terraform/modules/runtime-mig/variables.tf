variable "project_id" { type = string }
variable "region" { type = string }
variable "customer" { type = string }
variable "subnetwork" { type = string }
variable "image_project" {
  description = "Project holding Packer-built golden images (<product>-<version>)"
  type        = string
}
variable "products" {
  type = map(object({
    version         = string
    service_account = string
    config          = map(string)
    canary          = object({ version = string, percent = number })
  }))
}
variable "machine_type" {
  type    = string
  default = "e2-standard-2"
}
variable "min_replicas" {
  type    = number
  default = 3
}
variable "max_replicas" {
  type    = number
  default = 9
}
variable "labels" {
  type    = map(string)
  default = {}
}
