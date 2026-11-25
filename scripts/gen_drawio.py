#!/usr/bin/env python3
"""Generate draw.io (mxfile) architecture diagrams for Cloud Run, GKE and Instance Group runtimes."""
import sys, json, os
from xml.sax.saxutils import quoteattr

CONT = "rounded=1;whiteSpace=wrap;html=1;fillColor=none;dashed=0;verticalAlign=top;align=left;spacingLeft=8;fontStyle=1;strokeWidth=2;"
def S(fill, stroke="#666666"):
    return f"rounded=1;whiteSpace=wrap;html=1;fillColor={fill};strokeColor={stroke};"

ICONS = json.load(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "gcp_icons.json")))
# first match wins: keyword in label -> GCP icon (official Google Cloud icons from the draw.io gcp2 library)
ICON_RULES = [
    ("Artifact Registry", "Artifact Registry"), ("Secret Manager", "Key Management Service"),
    ("Cloud SQL", "Cloud SQL"), ("BigQuery", "BigQuery"), ("GCS", "Cloud Storage"), ("buckets", "Cloud Storage"),
    ("Load Balancer", "Cloud Load Balancing"), ("Edge LB", "Cloud Load Balancing"),
    ("Backend service", "Cloud Load Balancing"), ("Serverless NEG", "Cloud Load Balancing"), ("Gateway", "Cloud Load Balancing"),
    ("Cloud Run", "Cloud Run"), ("GKE", "Kubernetes Engine"), ("Autopilot", "Kubernetes Engine"),
    ("Instance template", "Compute Engine"), ("Regional MIG", "Compute Engine"), ("MIG", "Compute Engine"), ("Private instances", "Compute Engine"), ("Ansible runners", "Compute Engine"),
    ("Artifact Registry", "Artifact Registry"), ("Secret Manager", "Key Management Service"), ("KMS", "Key Management Service"),
    ("Logging / Monitoring", "Cloud Monitoring"), ("Logging", "Cloud Logging"), ("Monitoring", "Cloud Monitoring"), ("Workload Identity", "IAM"), ("IAM", "IAM"),
    ("Shared VPC", "Cloud Network"), ("VPC", "Cloud Network"), ("DNS", "Cloud DNS"), ("Cloud Armor", "Cloud Armor"), ("CI (GitHub", "Cloud Build"),
]

DISPLAY = {"Key Management Service": "Secret Manager / Cloud KMS", "Cloud Network": "VPC (Shared VPC)", "Cloud Load Balancing": "Cloud Load Balancing",
           "Kubernetes Engine": "GKE", "Compute Engine": "Compute Engine (MIG)", "Cloud Build": "CI (build/deploy)", "IAM": "IAM / Workload Identity"}

class D:
    def __init__(self):
        self.cells, self.n = [], 1
        self.used = set()
    def box(self, label, x, y, w, h, style, parent="1", icon=None):
        is_plain = style.startswith("text;") or "fillColor=none" in style
        if icon is None and not is_plain and w >= 150:
            icon = next((ic for kw, ic in ICON_RULES if kw in label), None)
        if icon and not is_plain:
            if label.count("<br>") == 0:
                label = f"<b>{DISPLAY.get(icon, icon)}</b><br>{label}"
            style = "rounded=0;whiteSpace=wrap;html=1;fillColor=none;strokeColor=none;align=left;spacingLeft=38;"
            self.used.add(icon)
        self.n += 1
        cid = f"c{self.n}"
        self.cells.append(f'<mxCell id="{cid}" value={quoteattr(label)} style={quoteattr(style)} vertex="1" parent="{parent}"><mxGeometry x="{x}" y="{y}" width="{w}" height="{h}" as="geometry"/></mxCell>')
        if icon and not is_plain:
            self.n += 1
            sz = 28 if h < 60 else 34
            ist = "shape=image;html=1;verticalLabelPosition=bottom;verticalAlign=top;imageAspect=1;aspect=fixed;image=data:image/svg+xml," + ICONS[icon] + ";"
            self.cells.append(f'<mxCell id="i{self.n}" value="" style={quoteattr(ist)} vertex="1" parent="{parent}"><mxGeometry x="{x + 5}" y="{y + (h - sz) / 2}" width="{sz}" height="{sz}" as="geometry"/></mxCell>')
        return cid
    def cont(self, label, x, y, w, h, color):
        return self.box(label, x, y, w, h, CONT + f"strokeColor={color};fontColor={color};")
    def legend(self, x, y, w=1400):
        names = sorted(self.used)
        per_row = 5
        rows = (len(names) + per_row - 1) // per_row
        colw = (w - 30) // per_row
        self.cont("Icon key: which icon means which Google Cloud service", x, y, w, 50 + rows * 50, "#7f7f7f")
        for i, nm in enumerate(names):
            cx, cy = x + 20 + (i % per_row) * colw, y + 40 + (i // per_row) * 50
            self.n += 1
            ist = "shape=image;html=1;imageAspect=1;aspect=fixed;image=data:image/svg+xml," + ICONS[nm] + ";"
            self.cells.append(f'<mxCell id="k{self.n}" value="" style={quoteattr(ist)} vertex="1" parent="1"><mxGeometry x="{cx}" y="{cy}" width="34" height="34" as="geometry"/></mxCell>')
            self.n += 1
            self.cells.append(f'<mxCell id="kt{self.n}" value={quoteattr(DISPLAY.get(nm, nm))} style="text;html=1;align=left;verticalAlign=middle;whiteSpace=nowrap;fontSize=13;" vertex="1" parent="1"><mxGeometry x="{cx + 42}" y="{cy}" width="{colw - 50}" height="34" as="geometry"/></mxCell>')
    def edge(self, a, b, label="", dashed=False, exit=None, entry=None):
        """Always solid. exit/entry = (x, y) fractions on the source/target shape."""
        self.n += 1
        st = "edgeStyle=orthogonalEdgeStyle;rounded=1;html=1;endArrow=block;endFill=1;strokeWidth=2;strokeColor=#333333;"
        if label:
            if label.isdigit():
                st += "labelBackgroundColor=#FFD966;fontColor=#990000;fontStyle=1;fontSize=14;"
            else:
                st += "labelBackgroundColor=#ffffff;fontSize=12;"
        if exit:
            st += f"exitX={exit[0]};exitY={exit[1]};exitDx=0;exitDy=0;"
        if entry:
            st += f"entryX={entry[0]};entryY={entry[1]};entryDx=0;entryDy=0;"
        self.cells.append(f'<mxCell id="e{self.n}" value={quoteattr(label)} style={quoteattr(st)} edge="1" parent="1" source="{a}" target="{b}"><mxGeometry relative="1" as="geometry"/></mxCell>')
    def xml(self, name, page_h=1169):
        body = "\n".join(self.cells)
        return f'''<mxfile host="app.diagrams.net"><diagram name={quoteattr(name)} id="d1"><mxGraphModel dx="1400" dy="900" grid="1" gridSize="10" guides="1" tooltips="1" connect="1" arrows="1" fold="1" page="1" pageScale="1" pageWidth="1654" pageHeight="{page_h}" math="0" shadow="0"><root><mxCell id="0"/><mxCell id="1" parent="0"/>
{body}
</root></mxGraphModel></diagram></mxfile>'''

BLUE, GREEN, YEL, ORG, GREY, RED = S("#dae8fc","#6c8ebf"), S("#d5e8d4","#82b366"), S("#fff2cc","#d6b656"), S("#ffe6cc","#d79b00"), S("#f5f5f5"), S("#f8cecc","#b85450")

def build(runtime):
    d = D()
    d.box(f"<b>Multi-Tenant GCP Platform: {runtime['title']}</b><br>200+ customers x 4 envs x 15-20 products | shown for one customer-env project; the same stack is stamped for dev, stage, uat and prod", 20, 10, 1400, 50, "text;html=1;align=left;fontSize=16;")
    # Org hierarchy
    org = d.cont("GCP Organization / Folders: platform/ , customers/&lt;customer&gt;/{dev,stage,uat,prod}", 20, 70, 1400, 95, "#7f7f7f")
    d.box("Org Policies<br>(region, no external IP, CMEK)", 40, 100, 200, 55, YEL)
    d.box("Folder: platform", 260, 100, 160, 40, GREY)
    d.box("Folder: customers/&lt;customer&gt;", 440, 100, 200, 40, GREY)
    d.box("Terraform project factory<br>(1 module call per customer-env)", 660, 100, 240, 40, GREY)
    d.box("Billing labels: customer, env, product", 920, 100, 240, 40, GREY)
    # Shared services
    sh = d.cont("Project: shared-services (platform folder)", 20, 170, 330, 720, "#b85450")
    gh = d.box("GitHub / Bitbucket<br>(app + infra repos, Actions)", 40, 210, 290, 50, ORG)
    an = d.box("Ansible runners<br>(MIG, private, OS config + deploy)", 40, 280, 290, 50, ORG)
    ar = d.box("Artifact Registry<br>images/charts tagged &lt;product&gt;:&lt;version&gt;[-&lt;customer&gt;]", 40, 350, 290, 60, YEL)
    sm = d.box("Secret Manager + Cloud KMS (CMEK)", 40, 430, 290, 40, YEL)
    vpc = d.box("Shared VPC host project<br>+ Cloud DNS + Cloud NAT", 40, 490, 290, 50, BLUE)
    obs = d.box("Cloud Logging / Monitoring<br>(org log sink, per-customer scopes)", 40, 560, 290, 50, GREY)
    rel = d.box("Release catalog (Terraform vars / Helm values)<br>customer -> product -> version + overrides", 40, 630, 290, 70, GREEN)
    d.box("Workload Identity Federation<br>(GitHub OIDC, no SA keys)", 40, 710, 290, 50, RED)
    # Edge
    user = d.box("Customer users", 380, 190, 120, 40, GREY)
    lb = d.box("Global External HTTPS LB<br>+ Cloud Armor + managed certs<br>host: &lt;customer&gt;.&lt;product&gt;.example.com", 540, 175, 300, 70, BLUE)
    d.edge(user, lb, "HTTPS")
    # Customer env project
    cp = d.cont("Project: &lt;customer&gt;-&lt;env&gt; (one per customer per env; SERVICE PROJECT of Shared VPC)", 380, 270, 700, 620, "#6c8ebf")
    # Data project
    dp = d.cont("Project: &lt;customer&gt;-data (shared across THAT customer's envs only)", 1110, 270, 310, 620, "#82b366")
    sql = d.box("Cloud SQL / AlloyDB<br>per-env DB + schema; read-replica<br>or authorized access across envs", 1130, 320, 270, 70, GREEN)
    gcs = d.box("GCS buckets<br>(uniform ACL, CMEK, per-env prefix)", 1130, 410, 270, 55, GREEN)
    bq = d.box("BigQuery datasets<br>authorized views for cross-env sharing", 1130, 480, 270, 55, GREEN)
    ps = d.box("Pub/Sub (cross-env events)", 1130, 550, 270, 40, GREEN)
    d.box("IAM: only &lt;customer&gt; env SAs granted<br>VPC-SC perimeter per customer<br>=> no cross-customer data path", 1130, 620, 270, 70, RED)
    ids = runtime["draw"](d, cp)
    d.edge(lb, ids["ingress"], "serverless NEG / backend" if runtime["key"]=="cloudrun" else "backend")
    for t in ids["data"]:
        d.edge(t, sql, "private IP / PSC", dashed=True)
    d.edge(ids["data"][0], gcs, "", dashed=True)
    d.edge(ids["data"][0], bq, "", dashed=True)
    d.edge(ar, ids["pull"], "pull image", dashed=True)
    d.edge(gh, ar, "build + push")
    d.edge(an, ids["deploy"], "deploy / configure")
    d.edge(sm, ids["data"][0], "secrets (WI / SA)", dashed=True)
    d.edge(rel, ids["deploy"], "version pin", dashed=True)
    d.legend(20, 910)
    return d

def cloudrun(d, cp):
    vpcn = d.box("Serverless VPC Access connector / Direct VPC egress<br>(Shared VPC subnet)", 400, 560, 660, 40, BLUE)
    ing = d.box("Serverless NEG + Internal/External Ingress", 400, 310, 660, 40, BLUE)
    a = d.box("<b>Cloud Run service</b><br>product-a<br>rev: v2.4.1 (cust-A cfg)", 400, 380, 200, 80, GREEN)
    b = d.box("<b>Cloud Run service</b><br>product-b<br>rev: v1.9.0 (cust-A cfg)", 620, 380, 200, 80, GREEN)
    c = d.box("<b>Cloud Run job</b><br>product-c batch<br>rev: v3.0.2", 840, 380, 200, 80, GREEN)
    d.box("Traffic splitting per revision (canary 5% -> 100%);<br>one service per product, image tag = customer's pinned version;<br>customer config via env vars + Secret Manager mounts", 400, 480, 660, 60, YEL, icon=False)
    sa = d.box("Per-service runtime SA (least privilege) + Eventarc / Cloud Scheduler / Tasks", 400, 620, 660, 40, GREY)
    dep = d.box("Deploy: Terraform google_cloud_run_v2_service<br>(image tag from release catalog) / gcloud run deploy", 400, 690, 660, 50, ORG)
    d.edge(a, vpcn); d.edge(b, vpcn); d.edge(c, vpcn)
    return {"ingress": ing, "data": [vpcn], "pull": a, "deploy": dep}

def gke(d, cp):
    ing = d.box("GKE Gateway / Ingress (Multi-cluster optional) + Istio/ASM", 400, 310, 660, 40, BLUE)
    cl = d.cont("GKE Autopilot/Standard cluster (regional, private nodes, Workload Identity, Dataplane V2)", 400, 360, 660, 330, "#6c8ebf")
    d.box("<b>Namespace: product-a</b><br>Helm release product-a<br>chart 2.4.1<br>values-&lt;customer&gt;.yaml", 420, 400, 190, 100, GREEN, icon="Kubernetes Engine")
    d.box("<b>Namespace: product-b</b><br>Helm release product-b<br>chart 1.9.0<br>values-&lt;customer&gt;.yaml", 630, 400, 190, 100, GREEN, icon="Kubernetes Engine")
    d.box("<b>Namespace: product-c</b><br>Helm release product-c<br>chart 3.0.2<br>values-&lt;customer&gt;.yaml", 840, 400, 190, 100, GREEN, icon="Kubernetes Engine")
    d.box("NetworkPolicy default-deny, ResourceQuota, PSS restricted, HPA/PDB per namespace", 420, 520, 610, 40, YEL)
    pods = d.box("Pods -> KSA bound to GSA (Workload Identity) -> Cloud SQL Auth Proxy / PSC", 420, 580, 610, 40, BLUE, icon="IAM")
    d.box("Argo CD / Config Sync (optional GitOps: one App per product per customer-env)", 420, 635, 610, 40, GREY)
    dep = d.box("Deploy: Terraform (cluster, node pools) + Helm provider / Argo CD<br>umbrella chart, values per customer-env", 400, 710, 660, 50, ORG)
    return {"ingress": ing, "data": [pods], "pull": pods, "deploy": dep}

def mig(d, cp):
    ing = d.box("Backend service + health checks (Internal / External LB)", 400, 310, 660, 40, BLUE)
    t = d.box("<b>Instance template</b> product-a-v2.4.1-&lt;customer&gt;<br>Custom/golden image from Packer (Artifact Registry / Image family)<br>startup script + Ansible pull", 400, 370, 320, 90, YEL, icon="Compute Engine")
    m1 = d.box("<b>Regional MIG</b> product-a<br>autoscaler (CPU / LB util), autohealing<br>zones a / b / c", 740, 370, 320, 90, GREEN)
    m2 = d.box("<b>Regional MIG</b> product-b<br>template v1.9.0<br>rolling update, max surge 3 / unavailable 0", 740, 480, 320, 70, GREEN)
    d.box("Canary: 2nd instance template at 5% (version_target), then promote<br>Custom config baked by Ansible role vars per customer", 400, 480, 320, 70, YEL)
    nat = d.box("Private instances (no external IP) -> Cloud NAT, IAP TCP for admin<br>Per-MIG service account, OS Login, Shielded VM", 400, 570, 660, 50, BLUE)
    d.box("Persistent disks / Filestore (per env), snapshot schedule", 400, 635, 660, 40, GREY)
    dep = d.box("Deploy: Terraform google_compute_region_instance_group_manager<br>+ Ansible runners (rolling config)", 400, 710, 660, 50, ORG)
    d.edge(t, m1, "uses"); d.edge(t, m2, "", dashed=True)
    return {"ingress": ing, "data": [nat], "pull": t, "deploy": dep}


def overview():
    d = D()
    d.box("<b>Multi-Tenant GCP Platform: Overall Architecture and Flow</b><br>15-20 products | 200+ customers | 4 envs each (dev, stage, uat, prod) | GKE, Cloud Run, Instance Groups", 20, 10, 1000, 50, "text;html=1;align=left;fontSize=16;")
    users = d.box("<b>End users</b><br>(customers' staff)", 1430, 12, 140, 45, GREY)
    # ---- shared control plane ----
    d.cont("Shared control plane (platform folder)", 20, 70, 360, 970, "#b85450")
    gh = d.box("<b>GitHub / Bitbucket</b><br>app + infra repos, release catalog", 40, 110, 330, 55, ORG)
    ci = d.box("<b>CI: GitHub Actions</b><br>build, plan, apply", 40, 190, 330, 55, ORG, icon="Cloud Build")
    ar = d.box("<b>Artifact Registry</b><br>images, charts", 40, 280, 160, 55, YEL, icon="Artifact Registry")
    tf = d.box("<b>Terraform</b><br>project factory", 210, 280, 160, 55, GREEN)
    d.box("<b>Secret Manager / KMS</b><br>secrets and keys per customer", 40, 410, 330, 55, YEL, icon="Key Management Service")
    d.box("<b>Workload Identity</b><br>GitHub OIDC, no SA keys", 40, 490, 330, 55, RED, icon="IAM")
    an = d.box("<b>Ansible runners</b><br>private MIG, configure VMs", 40, 570, 330, 55, ORG, icon="Compute Engine")
    d.box("<b>Logging and Monitoring</b><br>labels: customer, env, product", 40, 650, 330, 55, GREY, icon="Cloud Monitoring")
    d.box("<b>Shared VPC host</b><br>subnet per env and region, NAT", 40, 730, 330, 55, BLUE, icon="Cloud Network")
    d.box("<b>Org policies</b><br>no external IP, no SA keys, no public SQL", 40, 810, 330, 55, RED)
    # ---- customers ----
    org = d.cont("Organization > folder customers/   (customers/&lt;customer&gt;/&lt;env&gt;)", 400, 70, 1180, 970, "#6c8ebf")
    acme = d.cont("Folder customers/acme: billing (Cloud Run) + reports (GKE)", 420, 110, 1140, 410, "#6c8ebf")
    envs = [("dev", "2.5.0-rc1"), ("stage", "2.4.1"), ("uat", "2.4.1"), ("prod", "2.4.1")]
    data = d.cont("Project pl-acme-data: shared across ONLY acme's own environments", 435, 395, 1110, 110, "#82b366")
    proj = {}
    for i, (e, v) in enumerate(envs):
        x = 435 + i * 282
        proj[e] = d.cont(f"Project pl-acme-{e}", x, 150, 270, 215, "#6c8ebf")
        lb = d.box("<b>Cloud Load Balancing</b><br>+ Cloud Armor", x + 10, 190, 230, 50, BLUE, icon="Cloud Load Balancing")
        cr = d.box(f"<b>Cloud Run</b><br>billing v{v}", x + 10, 250, 230, 50, GREEN, icon="Cloud Run")
        gk = d.box("<b>GKE</b><br>reports v1.9.0", x + 10, 310, 230, 50, GREEN, icon="Kubernetes Engine")
        d.edge(lb, cr, "8" if e == "prod" else "")
        d.edge(lb, gk, "", exit=(1, 0.5), entry=(1, 0.5))
        d.edge(proj[e], data, "9" if e == "prod" else "", exit=(0.5, 1), entry=((x + 135 - 435) / 1110, 0))
        if e == "prod":
            d.edge(users, lb, "7", exit=(0.5, 1), entry=(0.9, 0))
    d.box("<b>Cloud SQL</b><br>non-prod: DB per env", 450, 435, 250, 50, GREEN, icon="Cloud SQL")
    d.box("<b>Cloud SQL</b><br>prod: dedicated, HA", 715, 435, 250, 50, GREEN, icon="Cloud SQL")
    d.box("<b>Cloud Storage</b><br>per-env + shared bucket", 980, 435, 270, 50, GREEN, icon="Cloud Storage")
    d.box("<b>BigQuery</b><br>per-env + shared dataset", 1260, 435, 270, 50, GREEN, icon="BigQuery")
    gprojs = []
    globex = d.cont("Folder customers/globex: billing at an OLDER version + legacy-erp on Instance Groups", 420, 540, 1140, 315, "#6c8ebf")
    for i, (e, canary) in enumerate([("dev", ""), ("stage", ""), ("uat", " (+canary)"), ("prod", " (+canary)")]):
        x = 435 + i * 282
        gp = d.cont(f"Project pl-globex-{e}", x, 580, 270, 160, "#6c8ebf")
        gprojs.append((gp, x))
        d.box("<b>Cloud Run</b><br>billing v2.3.7 (custom)", x + 10, 620, 250, 50, GREEN, icon="Cloud Run")
        d.box(f"<b>Compute Engine MIG</b><br>legacy-erp v3.0.2{canary}", x + 10, 680, 250, 50, GREEN, icon="Compute Engine")
    gdata = d.cont("Project pl-globex-data: shared across ONLY globex's own environments", 435, 760, 1110, 85, "#82b366")
    d.box("<b>Cloud SQL, Cloud Storage, BigQuery</b><br>per-env + shared (same pattern as acme)", 450, 790, 560, 50, GREEN, icon="Cloud SQL")
    for gp, gx in gprojs:
        d.edge(gp, gdata, "", exit=(0.5, 1), entry=((gx + 135 - 435) / 1110, 0))
    d.box("... 200+ customers: each catalog entry becomes a folder, 4 env projects and 1 data project (Terraform for_each)", 420, 875, 1140, 40, GREY)
    d.cont("Version divergence (catalog/customers.yaml)", 420, 935, 560, 95, "#d6b656")
    d.box("customer > product > runtime, version, env_versions, config, canary<br>custom config = env vars / ConfigMap / metadata (no forks)", 430, 968, 540, 50, YEL)
    d.cont("Runtimes in each env project", 1000, 935, 560, 95, "#82b366")
    d.box("<b>Cloud Run</b><br>service per product", 1010, 968, 175, 50, GREEN, icon="Cloud Run")
    d.box("<b>GKE</b><br>Helm release each", 1195, 968, 175, 50, GREEN, icon="Kubernetes Engine")
    d.box("<b>Compute Engine</b><br>MIG per product", 1380, 968, 170, 50, GREEN, icon="Compute Engine")
    # ---- flow ----
    d.edge(gh, ci, "1", exit=(0.5, 1), entry=(0.5, 0))
    d.edge(ci, ar, "2", exit=(0.24, 1), entry=(0.5, 0))
    d.edge(ci, tf, "3", exit=(0.76, 1), entry=(0.5, 0))
    d.edge(tf, org, "4", exit=(1, 0.5), entry=(0, (307 - 70) / 870))
    d.edge(ar, org, "5", exit=(0.5, 1), entry=(0, (372 - 70) / 870))
    d.edge(an, globex, "6", exit=(1, 0.5), entry=(0, (597 - 540) / 215))
    d.cont("Flow: where to where", 20, 1060, 1560, 135, "#7f7f7f")
    d.box("<b>1</b> Developer pushes code or a catalog PR to GitHub<br><b>2</b> CI builds the image/chart and pushes it to Artifact Registry<br><b>3</b> CI runs Terraform using Workload Identity (no keys)", 40, 1095, 500, 85, "text;html=1;align=left;verticalAlign=top;fontSize=13;whiteSpace=wrap;")
    d.box("<b>4</b> Terraform creates the customer folders, projects, runtimes, LB, data<br><b>5</b> Runtimes pull images from Artifact Registry<br><b>6</b> Ansible runners configure the MIG VMs", 560, 1095, 500, 85, "text;html=1;align=left;verticalAlign=top;fontSize=13;whiteSpace=wrap;")
    d.box("<b>7</b> End users hit the customer env through HTTPS LB + Cloud Armor<br><b>8</b> LB routes by hostname to the product's runtime (Cloud Run, GKE or MIG)<br><b>9</b> Services use the customer's data project (own envs only)", 1080, 1095, 490, 85, "text;html=1;align=left;verticalAlign=top;fontSize=13;whiteSpace=wrap;")
    d.legend(20, 1215, 1560)
    return d

def landing_zone():
    d = D()
    d.box("<b>Landing Zone: Organization, Folder and Project Design</b><br>Nesting = hierarchy. Policies and IAM set at a node are inherited by everything inside it.", 20, 10, 1300, 50, "text;html=1;align=left;fontSize=16;")
    org = d.cont("Organization: example.com  (Cloud Identity domain, single org, single billing account)", 20, 70, 1560, 900, "#7f7f7f")
    band = d.cont("Org-level controls (inherited by every folder and project)", 40, 105, 1520, 105, "#b85450")
    ctl = [("<b>IAM groups</b><br>admin, network, security, devops", "IAM", GREY), ("<b>Org policies</b><br>no ext IP, no SA keys, region lock", None, RED),
           ("<b>Billing</b><br>1 account, budgets per customer", None, GREY), ("<b>Org log sink</b><br>audit logs to observability prj", "Cloud Logging", GREY),
           ("<b>VPC Service Controls</b><br>perimeter per customer (opt.)", None, GREY), ("<b>Tags and labels</b><br>customer, env, product", None, GREY)]
    for i, (t, ic, st) in enumerate(ctl):
        d.box(t, 50 + i * 253, 140, 245, 55, st, icon=ic)
    # bootstrap
    d.cont("Folder: bootstrap  (design only)", 40, 235, 300, 180, "#7f7f7f")
    seed = d.box("<b>prj-seed</b><br>Terraform state bucket + seed SA", 55, 280, 270, 60, GREY)
    d.box("Created once by hand/CLI, then<br>everything else is Terraform", 55, 350, 270, 50, "text;html=1;align=left;fontSize=12;")
    # platform
    d.cont("Folder: platform  (shared services)", 360, 235, 560, 620, "#b85450")
    d.cont("Sub-folder: shared  (coded in terraform/live/platform)", 380, 280, 520, 130, "#b85450")
    sh = d.box("<b>prj-shared-services</b><br>Artifact Registry, Secret Manager/KMS,<br>CI + Workload Identity, Ansible runners", 395, 320, 490, 75, YEL, icon="Artifact Registry")
    d.cont("Sub-folder: network  (coded: host project + Shared VPC)", 380, 430, 520, 130, "#6c8ebf")
    net = d.box("<b>prj-net-host</b><br>Shared VPC, subnet per env and region,<br>Cloud NAT, DNS, private services access", 395, 470, 490, 75, BLUE, icon="Cloud Network")
    d.cont("Sub-folder: observability and security  (design only)", 380, 580, 520, 130, "#7f7f7f")
    d.box("<b>prj-observability</b><br>log sink bucket, metrics scopes,<br>Security Command Center", 395, 620, 490, 75, GREY, icon="Cloud Monitoring")
    d.box("Shared VPC host shares subnets to every customer env project (service projects).<br>Artifact Registry is read by every env project's runtime identity.", 380, 730, 520, 100, "text;html=1;align=left;verticalAlign=top;whiteSpace=wrap;fontSize=12;")
    # customers
    d.cont("Folder: customers  (coded: org policies attached here)", 940, 235, 620, 620, "#6c8ebf")
    for k, (name, y, h) in enumerate([("acme", 280, 230), ("globex", 530, 230)]):
        d.cont(f"Folder: {name}  (one per customer)", 955, y, 590, h, "#6c8ebf")
        for i, e in enumerate(["dev", "stage", "uat", "prod"]):
            x = 970 + i * 143
            d.cont(f"Folder: {e}", x, y + 40, 135, 90, "#6c8ebf")
            d.box(f"<b>prj-{name}-{e}</b>", x + 8, y + 75, 119, 45, GREEN)
        d.box(f"<b>prj-{name}-data</b>: shared across {name}'s envs only (Cloud SQL, Storage, BigQuery)", 970, y + 150, 560, 60, GREEN, icon="Cloud SQL")
    d.box("... 200+ customers: one folder + 4 env folders + 5 projects each, created from the catalog", 955, 775, 590, 55, GREY)
    d.cont("Customer onboarding flow", 20, 985, 1560, 120, "#82b366")
    steps = ["<b>1</b> PR adds the customer<br>to catalog/customers.yaml", "<b>2</b> CI plans, reviewers<br>approve", "<b>3</b> Terraform creates folder,<br>env folders, 4 env projects,<br>data project, attaches Shared VPC",
             "<b>4</b> Runtimes, LB, Cloud SQL,<br>buckets, datasets deployed", "<b>5</b> DNS + managed cert,<br>customer goes live"]
    ids = []
    for i, t in enumerate(steps):
        ids.append(d.box(t, 40 + i * 305, 1020, 270, 70, GREEN if i in (2, 3) else GREY, icon=False))
    for a, b in zip(ids, ids[1:]):
        d.edge(a, b)
    d.legend(20, 1125, 1560)
    return d

RUNTIMES = [
    {"key": "cloudrun", "title": "Cloud Run", "file": "cloud-run.drawio", "draw": cloudrun, "entry_id": None},
    {"key": "gke", "title": "GKE", "file": "gke.drawio", "draw": gke, "entry_id": None},
    {"key": "mig", "title": "Instance Groups (MIG)", "file": "instance-group.drawio", "draw": mig, "entry_id": None},
]

if __name__ == "__main__":
    out = sys.argv[1]
    for r in RUNTIMES:
        with open(f"{out}/{r['file']}", "w") as f:
            f.write(build(r).xml(r["title"]))
        print("wrote", r["file"])
    with open(f"{out}/architecture-overview.drawio", "w") as f:
        f.write(overview().xml("Architecture Overview", 1500))
    print("wrote architecture-overview.drawio")
    with open(f"{out}/landing-zone.drawio", "w") as f:
        f.write(landing_zone().xml("Landing Zone", 1450))
    print("wrote landing-zone.drawio")
