output "project_id" {
  value      = google_project.this.project_id
  depends_on = [google_project_service.api, google_compute_shared_vpc_service_project.attach]
}
output "project_number" { value = google_project.this.number }
