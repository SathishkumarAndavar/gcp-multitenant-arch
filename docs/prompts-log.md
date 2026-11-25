# Prompts log

Tool: Claude Code (Sonnet 5.5) in a local terminal session. Tools it ran: file read/write, shell (`terraform fmt/init/validate/console`, `helm lint/template`, `python3` to generate draw.io XML).

1. Provided the assignment PDF (`DevOps Architect Assignment Multi-Tenant GCP Platform.pdf`) as the brief.
2. Setup choices: new local repo; "reference implementation" depth for Terraform and Helm.
3. "give me the architecture diagrams in xml format that i can import to drawio" -> `docs/diagrams/*.drawio` via `scripts/gen_drawio.py`.
4. "GCP infrastructure architecture design ... is this done?" -> assessed the gap and wrote `docs/architecture.md`.
5. "Terraform scripts for infrastructure automation. for this?" -> `terraform/`.
6. "Helm charts for GKE deployment. for this" -> `helm/`.
7. "Documentation and code pushed to a public GitHub or Bitbucket repository" and "reiterate and create everything for this scenario" -> README, CI workflow, Ansible, this log.

Human review is still needed on design decisions (project-per-customer-env, shared non-prod SQL instance) and on IAM role breadth for `tf-deployer`.

## Verbatim user prompts (in order)

1. (Provided the assignment PDF "DevOps Architect Assignment: Multi-Tenant GCP Platform" - full brief reproduced below.)
2. "give me the architecture diagrams in xml format that i can import to drawio"
3. "GCP infrastructure architecture design covering the four environments, the multi-product and multi-customer model, version divergence and data sharing. is this done?"
4. "Terraform scripts for infrastructure automation. for this?"
5. "No create a arch diagram" (re: writing docs/architecture.md first)
6. "Helm charts for GKE deployment. for this"
7. "Documentation and code pushed to a public GitHub or Bitbucket repository, with the link shared with us for review. also please"
8. "reiterate and create everything for this scenario"
9. "No, docs/architecture.md i want draw.io"
10. "need gcp icons in the architecture diagram"
11. "keep the icons only , inside you can update icons with service name which icon means to which"
12. "diagram is not readable" (with screenshot)
13. "dotted lines are not good.. and there is no flow where to where and there is nothing about landing zone design and folder structure and org design"
14. "create a parallel agent and validate all, i am about to share we dont have much time"

### Assignment brief (verbatim summary of the PDF)
Design a multi-tenant, multi-product GCP infrastructure for four environments, then prove it with architecture diagrams, Terraform and Helm charts pushed to a public repository. 15-20 products, 200+ customers, envs dev/stage/uat/prod, runtimes GKE / Cloud Run / Instance Groups, multi-product tenancy per customer project, version divergence with customer-specific customizations, data sharing between a customer's own envs, shared GitHub/Bitbucket and Ansible runners. Deliverables: architecture design, three separate diagrams (Cloud Run, GKE, Instance Group), Terraform, Helm charts, docs + code in a public repo, and this prompts log.
