variable "project_id" { type = string }
variable "folder_id" { type = string }
variable "billing_account" { type = string }
variable "labels" {
  type    = map(string)
  default = {}
}
variable "apis" {
  type    = list(string)
  default = ["compute.googleapis.com", "iam.googleapis.com", "logging.googleapis.com", "monitoring.googleapis.com"]
}
variable "host_project_id" {
  type    = string
  default = ""
}
