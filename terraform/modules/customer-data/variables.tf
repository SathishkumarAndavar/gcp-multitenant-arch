variable "project_id" { type = string }
variable "customer" { type = string }
variable "region" { type = string }
variable "envs" { type = list(string) }
variable "private_network_id" { type = string }
variable "env_members" {
  description = "env => { product => IAM member (serviceAccount:...) } for that env. Keys must be plan-time known."
  type        = map(map(string))
}
variable "bq_location" {
  type    = string
  default = "US"
}
variable "sql_tier_prod" {
  type    = string
  default = "db-custom-4-16384"
}
variable "sql_tier_nonprod" {
  type    = string
  default = "db-custom-2-8192"
}
variable "labels" {
  type    = map(string)
  default = {}
}
