output "instance_groups" { value = { for k, m in google_compute_region_instance_group_manager.this : k => m.instance_group } }
output "health_checks" { value = { for k, h in google_compute_health_check.this : k => h.id } }
