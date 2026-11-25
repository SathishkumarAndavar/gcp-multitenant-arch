output "sql_connection_names" { value = { for e, i in local.env_to_instance : e => google_sql_database_instance.this[i].connection_name } }
output "shared_bucket" { value = google_storage_bucket.shared.name }
output "shared_dataset" { value = google_bigquery_dataset.shared.dataset_id }
