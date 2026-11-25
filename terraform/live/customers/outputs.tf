output "customer_env_projects" { value = { for k, m in module.env_project : k => m.project_id } }
output "data_projects" { value = { for k, m in module.data_project : k => m.project_id } }
output "resolved_versions" {
  description = "Effective product version per customer/env/product (version divergence view)"
  value       = { for k, p in local.products : k => p.version }
}
output "edge" { value = { for k, m in module.edge : k => { ip = m.ip_address, hosts = m.hostnames } } }
output "gke_helm_values" {
  description = "Per customer-env cluster + per-product Helm values"
  value       = { for k, m in module.gke : k => { cluster = m.cluster_name, location = m.cluster_location, products = m.helm_values } }
}
