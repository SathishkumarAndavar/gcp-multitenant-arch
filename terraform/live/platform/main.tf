locals {
  shared_id = "${var.prefix}-shared"
  host_id   = "${var.prefix}-net"
  # one /20 per env x region for VM-based runtimes (Cloud Run Direct VPC egress, MIG)
  env_idx    = { for i, e in var.envs : e => i }
  region_idx = { for i, r in var.regions : r => i }
  subnets    = { for p in setproduct(var.envs, var.regions) : "${p[0]}-${p[1]}" => { env = p[0], region = p[1], cidr = cidrsubnet("10.0.0.0/12", 8, local.env_idx[p[0]] * 8 + local.region_idx[p[1]]) } }
}

resource "google_folder" "platform" {
  display_name = "platform"
  parent       = "organizations/${var.org_id}"
}
resource "google_folder" "customers" {
  display_name = "customers"
  parent       = "organizations/${var.org_id}"
}

module "shared" {
  source          = "../../modules/project"
  project_id      = local.shared_id
  folder_id       = google_folder.platform.name
  billing_account = var.billing_account
  labels          = { purpose = "shared-services" }
  apis = ["compute.googleapis.com", "iam.googleapis.com", "iamcredentials.googleapis.com", "artifactregistry.googleapis.com",
  "secretmanager.googleapis.com", "cloudkms.googleapis.com", "logging.googleapis.com", "monitoring.googleapis.com", "sts.googleapis.com", "cloudresourcemanager.googleapis.com", "cloudbilling.googleapis.com", "serviceusage.googleapis.com"]
}
module "host" {
  source          = "../../modules/project"
  project_id      = local.host_id
  folder_id       = google_folder.platform.name
  billing_account = var.billing_account
  labels          = { purpose = "shared-vpc-host" }
  apis            = ["compute.googleapis.com", "servicenetworking.googleapis.com", "dns.googleapis.com", "container.googleapis.com"]
}
resource "google_compute_shared_vpc_host_project" "host" {
  project = module.host.project_id
}

# ---- Shared VPC ----
resource "google_compute_network" "vpc" {
  project                 = module.host.project_id
  name                    = "shared-vpc"
  auto_create_subnetworks = false
}
resource "google_compute_subnetwork" "env" {
  for_each                 = local.subnets
  project                  = module.host.project_id
  name                     = each.key
  region                   = each.value.region
  network                  = google_compute_network.vpc.id
  ip_cidr_range            = each.value.cidr
  private_ip_google_access = true
  log_config { aggregation_interval = "INTERVAL_10_MIN" }
}
resource "google_compute_router" "r" {
  for_each = toset(var.regions)
  project  = module.host.project_id
  name     = "router-${each.key}"
  region   = each.key
  network  = google_compute_network.vpc.id
}
resource "google_compute_router_nat" "nat" {
  for_each                           = toset(var.regions)
  project                            = module.host.project_id
  name                               = "nat-${each.key}"
  router                             = google_compute_router.r[each.key].name
  region                             = each.key
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
}
# Private services access for Cloud SQL
resource "google_compute_global_address" "psa" {
  project       = module.host.project_id
  name          = "psa-range"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  address       = "10.200.0.0" # pinned outside the GKE supernets
  prefix_length = 16
  network       = google_compute_network.vpc.id
}
resource "google_service_networking_connection" "psa" {
  network                 = google_compute_network.vpc.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.psa.name]
}
# LB health checks reach MIGs
resource "google_compute_firewall" "lb_health" {
  project       = module.host.project_id
  name          = "allow-lb-health"
  network       = google_compute_network.vpc.id
  source_ranges = ["130.211.0.0/22", "35.191.0.0/16"]
  target_tags   = ["allow-lb-health"]
  allow {
    protocol = "tcp"
    ports    = ["8080"]
  }
}
resource "google_compute_firewall" "iap_ssh" {
  project       = module.host.project_id
  name          = "allow-iap-ssh"
  network       = google_compute_network.vpc.id
  source_ranges = ["35.235.240.0/20"]
  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
}

# ---- Artifact Registry (images + helm charts) ----
resource "google_artifact_registry_repository" "images" {
  project       = module.shared.project_id
  location      = var.default_region
  repository_id = "products"
  format        = "DOCKER"
  description   = "Product images: <product>:<version>"
}
resource "google_artifact_registry_repository" "charts" {
  project       = module.shared.project_id
  location      = var.default_region
  repository_id = "charts"
  format        = "DOCKER" # OCI helm charts
}

# ---- GitHub Actions -> GCP via Workload Identity Federation (no keys) ----
resource "google_iam_workload_identity_pool" "github" {
  project                   = module.shared.project_id
  workload_identity_pool_id = "github"
}
resource "google_iam_workload_identity_pool_provider" "github" {
  project                            = module.shared.project_id
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = "github-oidc"
  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.repository" = "assertion.repository"
    "attribute.owner"      = "assertion.repository_owner"
  }
  attribute_condition = "assertion.repository == '${var.github_org}/${var.github_repo}'"
  oidc { issuer_uri = "https://token.actions.githubusercontent.com" }
}
resource "google_service_account" "deployer" {
  project      = module.shared.project_id
  account_id   = "tf-deployer"
  display_name = "Terraform/Helm deployer (CI + Ansible runners)"
}
resource "google_service_account_iam_member" "wif" {
  service_account_id = google_service_account.deployer.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository/${var.github_org}/${var.github_repo}"
}
resource "google_folder_iam_member" "deployer" {
  for_each = toset(["roles/resourcemanager.projectCreator", "roles/resourcemanager.folderAdmin", "roles/compute.networkAdmin", "roles/owner"])
  folder   = google_folder.customers.name
  role     = each.value
  member   = "serviceAccount:${google_service_account.deployer.email}"
}
resource "google_project_iam_member" "deployer_host" {
  for_each = toset(["roles/compute.networkAdmin", "roles/resourcemanager.projectIamAdmin"])
  project  = module.host.project_id
  role     = each.value
  member   = "serviceAccount:${google_service_account.deployer.email}"
}

# Billing + Shared VPC admin + image/registry access the deployer needs (xpnAdmin must really be org-level
# for host/service projects in different folders; grant it out-of-band if org IAM is managed elsewhere).
resource "google_billing_account_iam_member" "deployer" {
  billing_account_id = var.billing_account
  role               = "roles/billing.user"
  member             = "serviceAccount:${google_service_account.deployer.email}"
}
resource "google_organization_iam_member" "deployer_xpn" {
  org_id = var.org_id
  role   = "roles/compute.xpnAdmin"
  member = "serviceAccount:${google_service_account.deployer.email}"
}
resource "google_project_iam_member" "deployer_shared" {
  for_each = toset(["roles/artifactregistry.repoAdmin", "roles/compute.imageUser"])
  project  = module.shared.project_id
  role     = each.value
  member   = "serviceAccount:${google_service_account.deployer.email}"
}

# ---- Guardrails on every customer project ----
resource "google_org_policy_policy" "no_external_ip" {
  name   = "${google_folder.customers.name}/policies/compute.vmExternalIpAccess"
  parent = google_folder.customers.name
  spec {
    rules {
      deny_all = "TRUE"
    }
  }
}
resource "google_org_policy_policy" "no_sa_keys" {
  name   = "${google_folder.customers.name}/policies/iam.disableServiceAccountKeyCreation"
  parent = google_folder.customers.name
  spec {
    rules {
      enforce = "TRUE"
    }
  }
}
resource "google_org_policy_policy" "no_public_sql" {
  name   = "${google_folder.customers.name}/policies/sql.restrictPublicIp"
  parent = google_folder.customers.name
  spec {
    rules {
      enforce = "TRUE"
    }
  }
}
