# Multi-Tenant, Multi-Product GCP Platform: Architecture

Scope: 15-20 products, 200+ customers, 4 environments each (dev/stage/uat/prod), runtimes GKE, Cloud Run, Instance Groups (MIG), shared GitHub + Ansible runners.
Diagrams (draw.io, importable): `docs/diagrams/cloud-run.drawio`, `gke.drawio`, `instance-group.drawio`.

## 1. Tenancy model

```
Organization
├── platform/                      shared-services project, Shared VPC host project
└── customers/
    └── <customer>/
        ├── dev/    project  pl-<customer>-dev     (service project of Shared VPC)
        ├── stage/  project  pl-<customer>-stage
        ├── uat/    project  pl-<customer>-uat
        ├── prod/   project  pl-<customer>-prod
        └──         project  pl-<customer>-data    (data shared across THIS customer's envs)
```

Decision: **project per customer per environment** (about 800 env projects + 200 data projects at 200 customers).
- Blast radius, IAM, quotas and billing are isolated per customer and per env. Cost reports use the `customer`/`env` labels and project grouping.
- Multi-product tenancy: all of a customer's products for an env live in that env's single project (one namespace / Cloud Run service / MIG per product), so "several products inside the same infrastructure/project" holds.
- Trade-off: more projects means project-factory automation, quota requests and API-enablement time. It is mitigated by the Terraform `project` module, driven by the catalog.
- Guardrails come from org policy on the `customers/` folder: no external IPs, no SA keys, no public Cloud SQL. At scale, add a VPC-SC perimeter per customer and CMEK.

## 2. Environments

| | dev | stage | uat | prod |
|---|---|---|---|---|
| Cloud Run min/max | 0/3 | 0/5 | 1/10 | 2/100 |
| MIG min/max | 1/2 | 1/3 | 2/4 | 3/12 |
| GKE release channel | RAPID | REGULAR | REGULAR | STABLE |
| Canary rollout | no | no | yes | yes |
| Deletion protection | off | off | off | on (SQL, Cloud Run, GKE) |
| Cloud SQL | shared non-prod instance, ZONAL | same | same | dedicated instance, REGIONAL, PITR |

Profiles live in `terraform/live/customers/main.tf` (`env_profiles`). Promotion: change the catalog version for dev, then stage, uat and prod in successive PRs. Recommended: split state per customer/env and gate each apply (the reference code uses one state for `live/customers` and one `apply` job gated by the GitHub `prod` environment).

## 3. Version divergence and customization

Single source of truth: `catalog/customers.yaml` (customer -> product -> runtime, version, per-env version, config, canary).
- Same product, different version per customer: `version`. Example: billing is 2.4.1 for acme and 2.3.7 for globex.
- Per-env promotion: `env_versions` (acme dev runs 2.5.0-rc1 while prod stays 2.4.1).
- Customer-specific customization is **configuration, not forks**: `config` becomes env vars (Cloud Run), a ConfigMap (GKE) or instance metadata (MIG). Anything that needs different code gets its own image tag (`billing:2.4.1-acme`) and flows through the same `version` field.
- Artifacts: images `<registry>/<product>:<version>` (Artifact Registry in shared-services); MIG golden images `<product>-<version>` (build pipeline/Packer out of scope); Helm chart `product` is generic and platform-versioned, so product versions only change `image.tag`.
- Rollout: Cloud Run revisions; GKE rolling update with `maxUnavailable: 0`; MIG proactive rolling update plus a canary instance template (`target_size.percent`) in uat and prod. Rollback means reverting the catalog line (or traffic to the previous revision).
- Verification: `terraform output resolved_versions` shows the effective version for every customer/env/product.

## 4. Data sharing between a customer's own environments

The customer's data project is the only shared boundary, and it is per customer, so there is no cross-customer path.
- **Cloud SQL (Postgres, private IP via Shared VPC)**: non-prod envs share one instance with one database per env; prod has its own instance. Sharing within non-prod is by DB-level grants, and prod to non-prod goes only through the shared dataset or bucket.
- **GCS**: a private bucket per env, plus a `<project>-shared` bucket that all of that customer's env runtime SAs can read and write.
- **BigQuery**: a private dataset per env, plus a `<customer>_shared` dataset (viewer for all env SAs). Recommended (not coded): authorized views for masked or sanitized prod data.
- IAM is granted only to that customer's runtime service accounts (`module.customer-data` `env_members`). Public access prevention is enforced, and SQL uses IAM auth.

## 5. Runtimes

All three share the edge: a global external HTTPS LB per customer-env with host-based routing (`<product>.<env>.<domain>`; prod omits the env), Cloud Armor (WAF rules) and managed certificates.
- **Cloud Run**: one service per product, ingress internal+LB only, Direct VPC egress into the env subnet, serverless NEG backend, a runtime SA per product.
- **GKE**: one regional Autopilot cluster per customer-env (private nodes, Workload Identity, a dedicated node SA) with a per-cluster subnet carved from supernets. Products deploy as Helm releases, one namespace each (`helm/charts/product`), exposed through the GKE Gateway API.
- **Instance Groups**: a regional MIG per product, a golden image per version (`<product>-<version>` in the shared-services project; the Packer template that builds it is out of scope here), no external IPs (Cloud NAT + IAP), autoscaling, autohealing, rolling update plus canary.

## 6. Networking, identity and shared infrastructure

- **Network**: a Shared VPC host project with one subnet per env x region (shared by Cloud Run and MIG), per-cluster GKE subnets, Cloud NAT per region, private services access for Cloud SQL, and health-check and IAP firewall rules.
- **Identity**: GitHub Actions uses Workload Identity Federation (no SA keys) to impersonate `tf-deployer`. Each product has its own runtime SA, and GKE KSAs map to GSAs through Workload Identity.
- **GitHub** holds the app repos, this infra repo and CI (`.github/workflows/deploy.yml`: validate + plan on PR; one apply job on merge, gated by a manual-approval GitHub environment. Per-env jobs are a recommended split).
- **Ansible runners** are a private MIG in shared-services (no external IP, WIF or the attached SA). They run post-provision configuration for MIG-based products and OS hardening. **Design only:** the runner MIG, inventory and `app.env.j2` template are not in this repo; `ansible/site.yml` is an illustrative playbook.
- **Observability** (design only, not in Terraform): an org-level log sink and a metrics scope per customer project. `customer`/`env`/`product` labels are applied by the code for cost allocation and alert routing.

## 7. Scale notes and known limits

- 1,000 projects means requesting quota and project-creation rate increases up front. Terraform state should be split per customer or per shard (the example runs one state to stay readable).
- GKE CIDR allocation uses `network_index` (unique per customer, 0-255), which supports 1,024 GKE customer-envs from the default supernets.
- Edge LB hostnames need DNS records pointing to `output edge` IPs (Cloud DNS module not included).
- The GKE Gateway cert (`<release>-cert`) and Secret Manager secret syncing are assumed to be provisioned alongside the cluster. This repo does not create them.
- Cloud Run invoker is `allUsers` at IAM level because ingress is restricted to the load balancer; access is controlled by Cloud Armor and application auth. Set `public_invoker = false` to require IAM.
- Secret Manager/KMS (CMEK) and VPC-SC are design items: the code enables APIs only.
- Not run against a real org. `terraform validate`, `helm lint` and `helm template` pass; a plan/apply needs real org, billing and credentials.

## Known gaps (reference implementation, not production-ready)

The Terraform validates (`terraform validate`) but has not been planned or applied against a real organization. A review found these items still open:

- **Shared VPC service-agent IAM is not wired.** GKE, Cloud Run (Direct VPC egress) and MIG creation need `compute.networkUser` on the env subnet for the Google service agents, `container.hostServiceAgentUser` on the host project, and `compute.imageUser` on the shared project for MIG images. These bindings are not in the code yet.
- **Remote state and CI variables.** The `backend "gcs"` block is commented out and CI passes no tfvars, so the workflow is illustrative. Enable the backend and pass `-var-file` before using it.
- **Tenant network isolation.** Subnets are shared per env and region, so customers share a network. Firewall rules do not isolate Cloud SQL private IPs. Production should use a subnet per customer-env (or a VPC per customer) and egress deny rules. Cloud Run's `public_invoker = true` default should be replaced with IAP or app-level auth.
- **Subnet sizing.** A /20 per env and region will not hold 200+ customers. Carve per-customer subnets from a supernet, as is already done for GKE.
- **Edge certificate rollover.** Adding a host replaces the managed certificate, which can interrupt HTTPS. Use Certificate Manager with a certificate map.
- **Cloud SQL IAM users.** IAM database users and `cloudsql.instanceUser` are not created, and `cloudsql.client` is granted project-wide on the data project.
- **Project ID collisions.** `pl-<customer>-<env>` IDs are globally unique across GCP and are not validated for length or collisions.

Fixed after review: plan-time `for_each` keys in `customer-data`, deployer roles (billing, org-level `xpnAdmin`, shared project), Workload Identity Federation restricted to one repository, `compute` API on the data project, `container` API on the host project, pinned private services range, `ENCRYPTED_ONLY` SQL, EU BigQuery location, and prod-only write access to the shared dataset.

Helm gaps still open: the release name and namespace must equal the product name (the Workload Identity binding is `<product>/<product>`); Terraform does not emit `gateway.host` or `SHARED_BUCKET` for GKE, so supply them in the values file; the Gateway's TLS certificate (`<release>-cert`) is not created by this repo; namespace default-deny, ResourceQuota and Pod Security labels shown in the GKE diagram are not created by the chart. Fixed after review: Gateway `HealthCheckPolicy`, `/tmp` emptyDir, explicit non-root UID, PDB `maxUnavailable`, cross-namespace Gateway attach, config key collisions, image tag label sanitising, and a clear failure when `gateway.host` is empty.
