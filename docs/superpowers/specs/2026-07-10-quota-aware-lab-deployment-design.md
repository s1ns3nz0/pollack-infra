# Quota-Aware Lab Deployment Design

## Goal

Deploy the complete data, Azure OpenAI, simulation, SOC, and red planes in
Korea Central under the subscription's current 20 regional vCPU limit, then
run infrastructure and workload-level verification before pushing the change.

## Current Constraint

The deployed simulation cluster consumes 12 vCPUs through three
`Standard_D4s_v5` nodes. The deployed SOC cluster consumes 8 vCPUs through two
`Standard_D4s_v5` nodes. This exhausts the regional and DSv5-family quota. The
red cluster currently requests another 8 vCPUs through two
`Standard_D4s_v5` nodes, so Azure rejects it during preflight validation.

The existing simulation topology must remain intact because its three pools
encode separate system, SITL, and SATCOM scheduling boundaries.

## Selected Design

The lab deployment will fit all planes into the existing 20-vCPU quota:

| Plane | Node pools | VM size | vCPUs |
| --- | ---: | --- | ---: |
| Simulation | 3 × 1 node | `Standard_D4s_v5` | 12 |
| SOC | 1 × 1 node | `Standard_D4s_v5` | 4 |
| Red | 2 × 1 node | `Standard_D2s_v5` | 4 |
| Total |  |  | 20 |

The SOC plane will retain a single system pool. This sacrifices control-plane
workload redundancy at the node level and is explicitly a lab-cost/quota
profile, not a production profile. The red plane retains separate system and
red-agent pools, including the red workload taint and label, but uses
`Standard_D2s_v5` nodes.

## Configuration Boundaries

`bicep/modules/aks-red.bicep` will accept parameters for system and user node
sizes and counts instead of hard-coding both pools to `Standard_D4s_v5`.
`bicep/main.bicep` will expose and forward those parameters. The lab parameter
file will select one `Standard_D2s_v5` node for each red pool.

The SOC Bicep template already exposes its system node count. The full-stack
deployment script will explicitly pass a lab SOC node count of one so reruns
converge the existing cluster from two nodes to one and release 4 vCPUs before
the red AKS deployment begins.

## Deployment Flow and Quota Guard

Before deploying AKS-dependent planes, `scripts/deploy-all.sh` will read the
regional vCPU usage and fail with a clear diagnostic if the configured lab
topology cannot fit the subscription limit. Its lab defaults will represent
the 20-vCPU topology above. Overrides will remain possible through environment
variables so larger subscriptions can deploy larger SOC or red nodes without
editing templates.

The deployment order remains data, Azure OpenAI, simulation, SOC, then red.
The SOC resize must complete before the subscription-scope red deployment is
submitted. Existing successfully deployed resources remain idempotent inputs
to subsequent reruns.

## Error Handling

The script will retain fail-fast shell behavior. Quota diagnostics will show
current usage, limit, and the configured topology's required vCPUs. Azure ARM
errors will remain visible and cause a nonzero exit. No script path will delete
or recreate an existing cluster automatically.

If Azure does not release quota immediately after the SOC scale-down, the
script will poll regional vCPU usage for a bounded period before failing with
the observed values. A rerun will safely continue from the converged state.

## Verification

Verification must be fresh and include:

1. Bicep compilation or validation for every changed template and parameter
   file.
2. Shell syntax validation for changed scripts.
3. A complete `deploy-all.sh` run with successful ARM deployment states.
4. Azure checks confirming all three AKS clusters are `Succeeded` and
   `Running`, with the expected pool counts and VM sizes.
5. Kubernetes API connectivity and node readiness for sim, SOC, and red.
6. Red-plane checks for firewall, route, ACR, storage, managed identities,
   Workload Identity federation, and Azure OpenAI role assignment.
7. Repository-provided internal tests and deployment validation scripts in
   `fried-pollack-ai`, using the newly deployed red cluster where applicable.

Only after all applicable checks pass will implementation changes be committed
and pushed. Existing unrelated working-tree changes must be preserved and
must not be overwritten.

## Non-Goals

- Automated Azure support-ticket creation for quota increases.
- Destructive recreation or downsizing of the simulation cluster.
- Production high-availability guarantees for the lab SOC cluster.
- Unrelated refactoring of the infrastructure or application repositories.
