output "customers_folder_id" { value = google_folder.customers.name }
output "host_project_id" { value = module.host.project_id }
output "shared_project_id" { value = module.shared.project_id }
output "network_id" { value = google_compute_network.vpc.id }
output "network_self_link" { value = google_compute_network.vpc.self_link }
output "subnets" { value = { for k, s in google_compute_subnetwork.env : k => s.self_link } }
output "registry" { value = "${var.default_region}-docker.pkg.dev/${module.shared.project_id}/${google_artifact_registry_repository.images.repository_id}" }
output "wif_provider" { value = google_iam_workload_identity_pool_provider.github.name }
output "deployer_sa" { value = google_service_account.deployer.email }
