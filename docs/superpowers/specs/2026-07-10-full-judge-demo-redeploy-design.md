# Full Judge Demo Redeploy Design

## Goal

Replace the currently deployed Azure lab with a clean full deployment that
includes the red workload, ArgoCD, the local cyber operations staff dashboard,
the KPI dashboard, and kagent UI. Provide a guarded teardown command for future
use and verify the rebuilt environment end to end.

## Authorized Live Operation

The current Azure subscription resources owned by this lab will be deleted and
recreated during implementation. The authorized resource groups are exactly:

- `dah-data-rg`
- `dah-soc-rg`
- `dah-sim-rg`
- `dah-red-rg`

The corresponding AKS-managed node resource groups may also be deleted. No
other resource group is selected merely because its name begins with `dah-`.
The current subscription ID must match the explicit teardown argument before
deletion starts.

## Judge Demo Components

The one-command launcher will require three sibling checkouts by default:

- `pollack-infra`
- `fried-pollack-ai`
- `pollack-ai`

After Azure and Kubernetes deployment, it starts and verifies:

| Component | URL | Source |
| --- | --- | --- |
| kagent UI | `http://localhost:18080` | red AKS port-forward |
| ArgoCD | `https://localhost:18081` | red AKS port-forward |
| KPI Dashboard | `http://localhost:18082/kpi-dashboard.html` | generated static HTML |
| Cyber Operations Staff Dashboard | `http://localhost:18083` | local `pollack-ai` FastAPI server |

ArgoCD installation is enabled by default. `INSTALL_ARGOCD=false` remains an
explicit opt-out for troubleshooting or lower-cost iteration. The launcher
will install ArgoCD, wait for all required rollouts, apply the root app, start
the HTTPS port-forward, and verify an HTTP response before reporting READY.

The staff dashboard is started with the sibling `pollack-ai` checkout and its
existing `demo_snapshots/`. The launcher checks the required Python imports
before deployment and fails with an installation command if dependencies are
missing.

## Process Lifecycle

All local services use the existing detached-process helper and
`/tmp/fried-pollack-judge-demo/` runtime directory. The stop command owns these
process names:

- `kagent-ui`
- `argocd`
- `kpi-dashboard`
- `cyber-staff-dashboard`

Re-running the launcher reuses live PIDs and replaces stale PIDs. The summary
prints all four local URLs, Portal links, process logs, Kubernetes evidence,
and the stop command.

## Guarded Teardown

`scripts/destroy-all.sh` defaults to plan-only behavior. It prints the active
subscription and the exact target groups. Destruction requires both:

```bash
bash scripts/destroy-all.sh --execute --subscription <current-subscription-id>
```

The script will:

1. validate required commands and arguments;
2. require the supplied subscription to equal the active Azure CLI
   subscription;
3. stop local judge-demo processes;
4. discover node resource groups from the three owned AKS resources;
5. submit deletion for the four fixed resource groups;
6. wait until the fixed and discovered node groups no longer exist;
7. print an itemized deletion result.

Missing resource groups are successful no-ops so teardown can be resumed. ARM
deployment-history records are not billable resources and remain by default.
The script does not use a prefix wildcard and does not delete unrelated groups.

## Verification

Teardown unit tests stub Azure CLI and prove plan-only default, subscription
mismatch rejection, fixed allowlist behavior, missing-group idempotency, and
bounded polling. Live teardown verification records the groups before deletion
and proves all authorized groups are absent afterward.

Full redeployment verification requires:

- all five ARM deployments `Succeeded`;
- sim, SOC, and red AKS `Succeeded` and `Running`;
- all red nodes Ready;
- kagent and red application Deployments Available;
- Agent Ready, RemoteMCPServer Accepted, and `run_engagement` discovered;
- ArgoCD required workloads available;
- all four local dashboard URLs return successful responses;
- the KPI and staff dashboard responses contain their expected titles;
- a second local-dashboard start reuses all four PIDs;
- both repositories' applicable tests pass before push.

## Documentation

The infrastructure README will list the four local dashboards, make ArgoCD the
default full-demo behavior, document `SOC_REPO`, and provide plan/execute
teardown examples with the subscription-match safeguard. The application judge
guide will point to the same full-deployment and teardown commands.

## Non-Goals

- Public internet exposure of any dashboard.
- Automatic deletion of unrelated `dah-*` resources.
- Deletion of the Azure subscription or tenant.
- Deploying the local staff dashboard as a new public Azure service.
