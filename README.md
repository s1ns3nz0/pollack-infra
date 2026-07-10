# pollak-infra

Azure infrastructure-as-code for the **pollak** UAV cyber range. Owns every
cloud resource for the three planes **and the seams between them**, because the
cross-plane boundary is a security artifact that must be versioned and reviewed
as one unit — not scattered across the three application repos.

## Why this repo exists

The range is composed of three isolated planes, each its own AKS cluster / VNet
/ resource group:

| Plane | Cluster | Role | App repo |
|---|---|---|---|
| red | `dah-red-aks` | attacker (offensive tooling) | `fried-pollack-ai` |
| sim | `dah-sim-aks` | target range (UAV SITL, GCS, datalink) | sim repo |
| soc | `dah-soc-aks` | defender (detection, dashboard) | `pollack-ai` |

Threat model is a **real trust boundary**: red runs live exploit tooling, so a
compromise must not reach sim/soc control planes, secrets, or nodes. Namespace
separation is soft multi-tenancy and is *not* a trust boundary here — hence
cluster-level isolation.

Several resources belong to **no single plane** and have no natural home in any
app repo. They live here:

- red↔sim VNet peering + Azure Firewall egress allowlist (the attack path)
- shared Azure Sentinel / Log Analytics workspace (sim tap writes append-only;
  soc reads — the detection path, with **no** direct sim↔soc network peering)
- private DNS zones (`*.pollak.store`, VNet-scoped split-horizon)
- role assignments / RBAC that enforce the plane boundary

## Layout

```
bicep/
  main.bicep          red plane (subscription-scope)
  sim.bicep           sim plane (subscription-scope)
  modules/            per-plane + shared modules
  params/
    lab*.bicepparam   author's live environment
    judge*.bicepparam reviewer Path B template (own subscription)
scripts/
  deploy-red-with-sim.sh   idempotent sim(skip-if-exists)+red provisioning
```

App-layer Kubernetes manifests (kustomize overlays) stay in each app repo; only
cloud infrastructure lives here. GitOps image-tag bumps happen in the app repos.

## Deploy

```bash
az deployment sub what-if --location koreacentral \
  --template-file bicep/main.bicep --parameters bicep/params/lab.bicepparam

scripts/deploy-red-with-sim.sh
```

Reviewers deploying into their own subscription: copy `bicep/params/judge.bicepparam`,
fill the `REPLACE_*` tokens, and point the scripts at it via `RED_PARAM_FILE` /
`SIM_PARAM_FILE`. See the red app repo's `deploy/JUDGE-DEPLOY.md` for the full
Path B runbook.

## Not yet coded

The cross-plane seam resources (shared Sentinel workspace, sim↔workspace DCR
ingestion, red↔sim peering hardening) are designed but not all committed here
yet. `bicep/modules/private-dns.bicep` is the first seam resource; peering and
the Sentinel workspace land as `modules/shared/` next.
