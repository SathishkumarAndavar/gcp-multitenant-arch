variable "project_id" { type = string }
variable "name" { type = string }
variable "env" { type = string }
variable "domain" { type = string }
variable "backends" {
  description = "product => backend. cloudrun: group=NEG id. mig: group=instance group, health_check=id"
  type = map(object({
    type         = string
    group        = string
    health_check = optional(string)
  }))
}
