# pollak-infra

Azure infrastructure-as-code for the **pollak** UAV cyber range. Owns every
cloud resource for the three planes **and the seams between them**, because the
cross-plane boundary is a security artifact that must be versioned and reviewed
as one unit — not scattered across the three application repos.

> **Related repos.** Red app (offensive agent + K8s overlays):
> [fried-pollack-ai](https://github.com/s1ns3nz0/fried-pollack-ai) — public;
> its `deploy/JUDGE-DEPLOY.md` is the reviewer runbook. SOC app: `pollack-ai`.

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
  shared.bicep        cross-plane seam (shared SIEM workspace) (subscription-scope)
  modules/
    shared/           seam modules (log-analytics; DCR/RBAC next)
    *.bicep           per-plane modules
  params/
    lab*.bicepparam   author's live environment
    judge*.bicepparam reviewer Path B template (own subscription)
scripts/
  deploy-red-with-sim.sh   idempotent sim(skip-if-exists)+red provisioning
```

Deploy the shared seam once (before or alongside the planes):

```bash
az deployment sub create --location koreacentral \
  --template-file bicep/shared.bicep --parameters bicep/params/lab-shared.bicepparam
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

## Seam status

Committed:
- `modules/private-dns.bicep` — split-horizon `*.pollak.store` private zones
- red↔sim / red↔soc VNet peering — in `modules/network-red.bicep` (gated on
  `simVnetResourceId` / `enableSoc`)
- `modules/shared/log-analytics.bicep` — the shared SIEM workspace
  (detection-path decoupling point), RBAC-only, daily ingestion cap
- `modules/shared/telemetry-ingest.bicep` — DCE + DCR + the four `UAV*_CL`
  custom tables the tap emits, plus the append-only role assignments:
  tap → Monitoring Metrics Publisher **on the DCR** (ingest only), SOC → Log
  Analytics Reader **on the workspace** (query only). Red gets nothing here.
- `shared.bicep` wires all of the above (subscription scope)

Wire-up pending (needs identities that don't exist until the sim/soc planes are
built): pass `tapPrincipalId` / `socReaderPrincipalId` to `shared.bicep` once the
tap and SOC managed identities exist — until then those role assignments are
skipped (empty-guarded). Extend `tableSchemas` in `telemetry-ingest.bicep` as the
tap emits more `UAV*_CL` tables.

The red app repo's Tier-0 emulation (`run.py --emit-soc`) reproduces the same
detection contract without deploying this pipeline; see that repo's
`deploy/JUDGE-DEPLOY.md`.
