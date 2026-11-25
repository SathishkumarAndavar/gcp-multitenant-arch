locals {
  catalog = yamldecode(file(var.catalog_path)).customers

  # Per-env sizing/safety profile. Promotion path: dev -> stage -> uat -> prod.
  env_profiles = {
    dev   = { idx = 0, min_instances = 0, max_instances = 3, mig_min = 1, mig_max = 2, protect = false, channel = "RAPID", cpu = "1", memory = "512Mi" }
    stage = { idx = 1, min_instances = 0, max_instances = 5, mig_min = 1, mig_max = 3, protect = false, channel = "REGULAR", cpu = "1", memory = "512Mi" }
    uat   = { idx = 2, min_instances = 1, max_instances = 10, mig_min = 2, mig_max = 4, protect = false, channel = "REGULAR", cpu = "1", memory = "1Gi" }
    prod  = { idx = 3, min_instances = 2, max_instances = 100, mig_min = 3, mig_max = 12, protect = true, channel = "STABLE", cpu = "2", memory = "2Gi" }
  }

  # customer x env
  customer_envs = merge([for c, cv in local.catalog : {
    for e in cv.envs : "${c}-${e}" => {
      key       = "${c}-${e}", customer = c, env = e, region = cv.region, domain = cv.domain,
      net_index = cv.network_index * 4 + local.env_profiles[e].idx
    }
  }]...)

  # customer x env x product, with version resolution (env override > product default)
  products = merge([for k, ce in local.customer_envs : {
    for p, pv in local.catalog[ce.customer].products : "${k}-${p}" => merge(ce, {
      product = p
      runtime = pv.runtime
      version = try(pv.env_versions[ce.env], pv.version)
      config  = try(pv.config, {})
      canary  = ce.env == "prod" || ce.env == "uat" ? try(pv.canary, null) : null
    })
  }]...)

  by_runtime = { for rt in ["cloudrun", "gke", "mig"] : rt => { for k, p in local.products : k => p if p.runtime == rt } }

  # customer-env => products grouped by runtime
  ce_runtime = { for k, ce in local.customer_envs : k => {
    cloudrun = { for pk, p in local.by_runtime.cloudrun : p.product => p if p.key == k }
    gke      = { for pk, p in local.by_runtime.gke : p.product => p if p.key == k }
    mig      = { for pk, p in local.by_runtime.mig : p.product => p if p.key == k }
  } }
  gke_ces = { for k, v in local.ce_runtime : k => local.customer_envs[k] if length(v.gke) > 0 }
  lb_ces  = { for k, v in local.ce_runtime : k => local.customer_envs[k] if length(v.cloudrun) + length(v.mig) > 0 }

  labels    = { managed_by = "terraform" }
  apis_base = ["compute.googleapis.com", "iam.googleapis.com", "logging.googleapis.com", "monitoring.googleapis.com", "artifactregistry.googleapis.com"]
}

check "unique_network_index" {
  assert {
    condition     = length(distinct([for c, cv in local.catalog : cv.network_index])) == length(local.catalog)
    error_message = "network_index must be unique per customer in catalog/customers.yaml"
  }
}

# ---------- folders: customers/<customer>/<env> ----------
resource "google_folder" "customer" {
  for_each     = local.catalog
  display_name = each.key
  parent       = var.customers_folder_id
}
resource "google_folder" "env" {
  for_each     = local.customer_envs
  display_name = each.value.env
  parent       = google_folder.customer[each.value.customer].name
}

# ---------- one project per customer-env (service project of Shared VPC) ----------
module "env_project" {
  source          = "../../modules/project"
  for_each        = local.customer_envs
  project_id      = "${var.prefix}-${each.value.customer}-${each.value.env}"
  folder_id       = google_folder.env[each.key].name
  billing_account = var.billing_account
  host_project_id = var.host_project_id
  labels          = merge(local.labels, { customer = each.value.customer, env = each.value.env })
  apis = concat(local.apis_base,
    length(local.ce_runtime[each.key].cloudrun) > 0 ? ["run.googleapis.com"] : [],
  length(local.ce_runtime[each.key].gke) > 0 ? ["container.googleapis.com"] : [])
}

# ---------- one data project per customer (shared by that customer's envs only) ----------
module "data_project" {
  source          = "../../modules/project"
  for_each        = local.catalog
  project_id      = "${var.prefix}-${each.key}-data"
  folder_id       = google_folder.customer[each.key].name
  billing_account = var.billing_account
  host_project_id = ""
  labels          = merge(local.labels, { customer = each.key, purpose = "data" })
  apis            = ["sqladmin.googleapis.com", "storage.googleapis.com", "bigquery.googleapis.com", "servicenetworking.googleapis.com", "iam.googleapis.com", "compute.googleapis.com"]
}
# Data project is attached to the shared VPC too so Cloud SQL gets a private IP on the shared network.
resource "google_compute_shared_vpc_service_project" "data" {
  for_each        = local.catalog
  host_project    = var.host_project_id
  service_project = module.data_project[each.key].project_id
}

# ---------- runtime identities ----------
module "identity" {
  source     = "../../modules/product-identity"
  for_each   = local.products
  project_id = module.env_project[each.value.key].project_id
  product    = each.value.product
}

module "data" {
  source             = "../../modules/customer-data"
  for_each           = local.catalog
  project_id         = module.data_project[each.key].project_id
  customer           = each.key
  region             = each.value.region
  envs               = each.value.envs
  private_network_id = var.network_id
  env_members        = { for e in each.value.envs : e => { for pk, p in local.products : p.product => module.identity[pk].member if p.customer == each.key && p.env == e } }
  bq_location        = startswith(each.value.region, "europe") ? "EU" : "US"
  labels             = merge(local.labels, { customer = each.key })
  depends_on         = [google_compute_shared_vpc_service_project.data]
}

# ---------- runtimes ----------
module "cloudrun" {
  source              = "../../modules/runtime-cloudrun"
  for_each            = { for k, v in local.ce_runtime : k => v.cloudrun if length(v.cloudrun) > 0 }
  project_id          = module.env_project[each.key].project_id
  region              = local.customer_envs[each.key].region
  customer            = local.customer_envs[each.key].customer
  env                 = local.customer_envs[each.key].env
  registry            = var.registry
  network             = var.network_self_link
  subnetwork          = var.subnets["${local.customer_envs[each.key].env}-${local.customer_envs[each.key].region}"]
  min_instances       = local.env_profiles[local.customer_envs[each.key].env].min_instances
  max_instances       = local.env_profiles[local.customer_envs[each.key].env].max_instances
  cpu                 = local.env_profiles[local.customer_envs[each.key].env].cpu
  memory              = local.env_profiles[local.customer_envs[each.key].env].memory
  deletion_protection = local.env_profiles[local.customer_envs[each.key].env].protect
  labels              = merge(local.labels, { customer = local.customer_envs[each.key].customer, env = local.customer_envs[each.key].env })
  products = { for p, v in each.value : p => {
    version         = v.version
    service_account = module.identity["${each.key}-${p}"].email
    config          = merge(v.config, { SQL_CONNECTION = try(module.data[v.customer].sql_connection_names[v.env], ""), SHARED_BUCKET = module.data[v.customer].shared_bucket })
  } }
  depends_on = [google_artifact_registry_repository_iam_member.cloudrun_pull]
}

module "mig" {
  source        = "../../modules/runtime-mig"
  for_each      = { for k, v in local.ce_runtime : k => v.mig if length(v.mig) > 0 }
  project_id    = module.env_project[each.key].project_id
  region        = local.customer_envs[each.key].region
  customer      = local.customer_envs[each.key].customer
  subnetwork    = var.subnets["${local.customer_envs[each.key].env}-${local.customer_envs[each.key].region}"]
  image_project = var.shared_project_id
  min_replicas  = local.env_profiles[local.customer_envs[each.key].env].mig_min
  max_replicas  = local.env_profiles[local.customer_envs[each.key].env].mig_max
  labels        = merge(local.labels, { customer = local.customer_envs[each.key].customer, env = local.customer_envs[each.key].env })
  products = { for p, v in each.value : p => {
    version         = v.version
    service_account = module.identity["${each.key}-${p}"].email
    config          = merge(v.config, { sql-connection = try(module.data[v.customer].sql_connection_names[v.env], "") })
    canary          = v.canary
  } }
}

# GKE: per-customer-env subnet (nodes + pod + service ranges) carved from supernets, created in the host project.
resource "google_compute_subnetwork" "gke" {
  for_each      = local.gke_ces
  project       = var.host_project_id
  name          = "gke-${each.key}"
  region        = each.value.region
  network       = var.network_id
  ip_cidr_range = cidrsubnet(var.gke_node_supernet, 12, each.value.net_index)
  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = cidrsubnet(var.gke_pods_supernet, 10, each.value.net_index)
  }
  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = cidrsubnet(var.gke_services_supernet, 12, each.value.net_index)
  }
  private_ip_google_access = true
}
module "gke" {
  source              = "../../modules/runtime-gke"
  for_each            = local.gke_ces
  project_id          = module.env_project[each.key].project_id
  region              = each.value.region
  customer            = each.value.customer
  env                 = each.value.env
  network             = var.network_id
  subnetwork          = google_compute_subnetwork.gke[each.key].self_link
  pods_range_name     = "pods"
  services_range_name = "services"
  registry            = var.registry
  release_channel     = local.env_profiles[each.value.env].channel
  deletion_protection = local.env_profiles[each.value.env].protect
  labels              = merge(local.labels, { customer = each.value.customer, env = each.value.env })
  products = { for p, v in local.ce_runtime[each.key].gke : p => {
    version         = v.version
    service_account = module.identity["${each.key}-${p}"].email
    config          = merge(v.config, { SQL_CONNECTION = try(module.data[v.customer].sql_connection_names[v.env], "") })
  } }
  depends_on = [google_compute_subnetwork.gke]
}

# One edge LB per customer-env for Cloud Run + MIG products (GKE products use GKE Gateway from the Helm chart).
module "edge" {
  source     = "../../modules/edge-lb"
  for_each   = local.lb_ces
  project_id = module.env_project[each.key].project_id
  name       = "${each.value.customer}-${each.value.env}"
  env        = each.value.env
  domain     = each.value.domain
  backends = merge(
    { for p, v in local.ce_runtime[each.key].cloudrun : p => { type = "cloudrun", group = module.cloudrun[each.key].negs[p], health_check = null } },
    { for p, v in local.ce_runtime[each.key].mig : p => { type = "mig", group = module.mig[each.key].instance_groups[p], health_check = module.mig[each.key].health_checks[p] } }
  )
}

# ---------- image pull access: Cloud Run service agent + GKE node SA read the shared registry ----------
resource "google_project_service_identity" "run" {
  provider = google-beta
  for_each = { for k, v in local.ce_runtime : k => v if length(v.cloudrun) > 0 }
  project  = module.env_project[each.key].project_id
  service  = "run.googleapis.com"
}
resource "google_artifact_registry_repository_iam_member" "cloudrun_pull" {
  for_each   = google_project_service_identity.run
  project    = var.registry_repository_project
  location   = var.registry_location
  repository = "products"
  role       = "roles/artifactregistry.reader"
  member     = "serviceAccount:${each.value.email}"
}
resource "google_artifact_registry_repository_iam_member" "gke_pull" {
  for_each   = local.gke_ces
  project    = var.registry_repository_project
  location   = var.registry_location
  repository = "products"
  role       = "roles/artifactregistry.reader"
  member     = module.gke[each.key].node_sa_member
}
