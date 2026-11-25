# Multi-Tenant GCP Platform (DevOps Architect Assignment)

Design and reference implementation for 15-20 products x 200+ customers x 4 envs on GCP (GKE, Cloud Run, Instance Groups).

| Deliverable | Where |
|---|---|
| Architecture design (draw.io) | [`docs/diagrams/architecture-overview.drawio`](docs/diagrams/architecture-overview.drawio); supporting notes in [`docs/architecture.md`](docs/architecture.md) |
| Landing zone / org / folder design (draw.io) | [`docs/diagrams/landing-zone.drawio`](docs/diagrams/landing-zone.drawio) |
| 3 runtime architecture diagrams (draw.io XML) | [`docs/diagrams/`](docs/diagrams) (`cloud-run`, `gke`, `instance-group`); generator: `scripts/gen_drawio.py` |
| Terraform | [`terraform/`](terraform): `live/platform` (org, VPC, registry, WIF), `live/customers` (catalog-driven), `modules/*` |
| Helm charts (GKE) | [`helm/charts/product`](helm/charts/product), values in `helm/values/` |
| Release catalog (version divergence) | [`catalog/customers.yaml`](catalog/customers.yaml) |
| CI / Ansible | `.github/workflows/deploy.yml`, `ansible/` |
| AI prompts log | [`docs/prompts-log.md`](docs/prompts-log.md) |

## How it works
1. `live/platform` once: folders, Shared VPC, Artifact Registry, GitHub OIDC, org policies.
2. Add a customer or change a version in `catalog/customers.yaml`; `live/customers` creates folders, projects, data project, runtimes and LB for each customer x env.
3. GKE products are deployed with Helm using values generated from `terraform output gke_helm_values`.

## Validation done
`terraform validate` (both roots), `terraform fmt`, `helm lint`, `helm template`, and catalog resolution via `terraform console`. Not applied to a real org.
# gcp-multitenant-arch
