output "negs" { value = { for k, n in google_compute_region_network_endpoint_group.neg : k => n.id } }
output "urls" { value = { for k, s in google_cloud_run_v2_service.this : k => s.uri } }
