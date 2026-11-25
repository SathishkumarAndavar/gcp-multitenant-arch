terraform {
  required_providers { google = { source = "hashicorp/google", version = ">= 5.30, < 7.0" } }
}
# Customer data project: per-env isolation + explicit sharing between THIS customer's envs only.
locals {
  # prod gets its own SQL instance; non-prod envs share one. Sharing prod<->non-prod only via the shared dataset/bucket.
  instances = {
    for k, v in {
      nonprod = [for e in var.envs : e if e != "prod"]
      prod    = [for e in var.envs : e if e == "prod"]
    } : k => v if length(v) > 0
  }
  env_to_instance = merge([for k, envs in local.instances : { for e in envs : e => k }]...)
  # Keys are env|product (known at plan time); member emails are only known after apply, so they stay in values.
  member_pairs = merge([for e, ms in var.env_members : { for prod, m in ms : "${e}|${prod}" => { e = e, m = m } }]...)
  prod_pairs   = { for k, v in local.member_pairs : k => v if v.e == "prod" }
}

resource "google_sql_database_instance" "this" {
  for_each            = local.instances
  project             = var.project_id
  name                = "${var.customer}-${each.key}"
  region              = var.region
  database_version    = "POSTGRES_15"
  deletion_protection = each.key == "prod"
  settings {
    tier              = each.key == "prod" ? var.sql_tier_prod : var.sql_tier_nonprod
    availability_type = each.key == "prod" ? "REGIONAL" : "ZONAL"
    ip_configuration {
      ipv4_enabled    = false
      private_network = var.private_network_id
      ssl_mode        = "ENCRYPTED_ONLY"
    }
    backup_configuration {
      enabled                        = true
      point_in_time_recovery_enabled = each.key == "prod"
    }
    database_flags {
      name  = "cloudsql.iam_authentication"
      value = "on"
    }
    user_labels = var.labels
  }
}

# One database per env inside its instance (shared instance, separate DBs).
resource "google_sql_database" "env" {
  for_each = local.env_to_instance
  project  = var.project_id
  name     = each.key
  instance = google_sql_database_instance.this[each.value].name
}

# Env-private bucket + shared bucket.
resource "google_storage_bucket" "env" {
  for_each                    = toset(var.envs)
  project                     = var.project_id
  name                        = "${var.project_id}-${each.key}"
  location                    = var.region
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  labels                      = merge(var.labels, { env = each.key })
}
resource "google_storage_bucket" "shared" {
  project                     = var.project_id
  name                        = "${var.project_id}-shared"
  location                    = var.region
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  labels                      = var.labels
}
resource "google_storage_bucket_iam_member" "env_own" {
  for_each = local.member_pairs
  bucket   = google_storage_bucket.env[each.value.e].name
  role     = "roles/storage.objectAdmin"
  member   = each.value.m
}
resource "google_storage_bucket_iam_member" "shared_rw" {
  for_each = local.member_pairs
  bucket   = google_storage_bucket.shared.name
  role     = "roles/storage.objectUser"
  member   = each.value.m
}

# BigQuery: private dataset per env + shared dataset for cross-env analytics.
resource "google_bigquery_dataset" "env" {
  for_each   = toset(var.envs)
  project    = var.project_id
  dataset_id = "${replace(var.customer, "-", "_")}_${each.key}"
  location   = var.bq_location
  labels     = merge(var.labels, { env = each.key })
}
resource "google_bigquery_dataset_iam_member" "env_own" {
  for_each   = local.member_pairs
  project    = var.project_id
  dataset_id = google_bigquery_dataset.env[each.value.e].dataset_id
  role       = "roles/bigquery.dataEditor"
  member     = each.value.m
}
resource "google_bigquery_dataset" "shared" {
  project    = var.project_id
  dataset_id = "${replace(var.customer, "-", "_")}_shared"
  location   = var.bq_location
  labels     = var.labels
}
resource "google_bigquery_dataset_iam_member" "shared" {
  for_each   = local.member_pairs
  project    = var.project_id
  dataset_id = google_bigquery_dataset.shared.dataset_id
  role       = "roles/bigquery.dataViewer"
  member     = each.value.m
}
# Only prod identities publish into the shared dataset; non-prod envs read it.
resource "google_bigquery_dataset_iam_member" "shared_writer" {
  for_each   = local.prod_pairs
  project    = var.project_id
  dataset_id = google_bigquery_dataset.shared.dataset_id
  role       = "roles/bigquery.dataEditor"
  member     = each.value.m
}

# Env SAs may connect to Cloud SQL (IAM auth); DB-level grants are applied by the app migration job.
resource "google_project_iam_member" "sql_client" {
  for_each = local.member_pairs
  project  = var.project_id
  role     = "roles/cloudsql.client"
  member   = each.value.m
}
