# Judge Demo Launcher Design

## Goal

Give a reviewer one command that deploys the complete Azure environment,
installs the application workload, starts local dashboard access, verifies the
result, and prints every useful local and Azure Portal link in one summary.

The documentation must also distinguish the short local demonstration from
the full Azure deployment so reviewers can choose the evidence level that fits
their available time, permissions, and budget.

## Reviewer Paths

The project exposes two primary review paths:

| Dimension | Short local demo | Full Azure judge deployment |
| --- | --- | --- |
| Command | `python demo.py` and `python run.py --emit-soc` | `bash scripts/deploy-judge-demo.sh` |
| Typical time | Minutes | Tens of minutes, subject to Azure provisioning |
| Cost | No Azure cost | AKS, Firewall, Log Analytics, Sentinel, AOAI, ACR, and Storage charges |
| Prerequisites | Python 3.11+ | Azure Owner access, Azure CLI login, quota, `kubectl`, `kubelogin`, Helm, and Python |
| AI model | No hosted model required; deterministic graph and built-in approval callback | kagent uses Azure OpenAI `gpt-4o-mini` through the `gpt-4o-soc` deployment for agent interaction and summarization |
| Model authority | No LLM participates in execution decisions | Azure OpenAI is advisory/orchestration-only; deterministic engagement gates, HITL policy, and ground-truth validation retain authority |
| Offline behavior | Fully runnable without network model access | Requires a healthy Azure OpenAI account, deployment, credentials, and approved egress |
| Attack pipeline | Real deterministic application code against the in-memory range | The same ToolServer and agent contract running on red AKS |
| SOC evidence | Emulated contract artifacts in `out/` | Real Log Analytics and Microsoft Sentinel resources |
| Isolation evidence | Architectural and test evidence | Separate sim, SOC, and red AKS clusters with live Azure boundaries |
| Dashboards | Generated KPI HTML | KPI HTML, kagent UI, optional ArgoCD, and Azure Portal deep links |
| Main limitation | Does not prove live Azure control-plane isolation | Higher cost, quota requirements, and longer setup |

The README will put this comparison near the quick-start section. It will not
describe the short demo as a live Sentinel detection or imply that the full
deployment is free or instantaneous. It will also avoid implying that the
hosted model autonomously authorizes attacks: `gpt-4o-mini` provides the
kagent-facing reasoning, interaction, and summary layer, while the ToolServer's
deterministic graph owns scope enforcement, risk classification, HITL routing,
execution policy, and ground-truth verification.

## Command Surface

`scripts/deploy-judge-demo.sh` is the reviewer entry point. It assumes
`pollack-infra` and `fried-pollack-ai` are sibling checkouts by default. The app
path can be overridden with `APP_REPO`.

The command performs these stages in order:

1. Run `scripts/deploy-all.sh` for data, Azure OpenAI, sim, SOC, and red.
2. Query deployment outputs for ACR, AKS, managed identities, and AOAI.
3. Build the immutable ToolServer image with ACR Tasks only when the requested
   repository tag is absent.
4. Run `fried-pollack-ai/scripts/bootstrap-red-agent.sh` against red AKS.
5. Generate `out/kpi-dashboard.html` in the app checkout.
6. Start or reuse local processes for dashboard access.
7. Verify Kubernetes readiness and MCP tool discovery.
8. Print a stable reviewer summary containing local URLs, Azure Portal links,
   runtime evidence, log locations, and the stop command.

The wrapper composes the existing deployment and bootstrap scripts. It does
not duplicate their Azure or Kubernetes implementation.

## Local Dashboard Processes

Runtime state lives under `/tmp/fried-pollack-judge-demo/`. Each background
process has a PID file and log file.

| Dashboard | Local URL | Process |
| --- | --- | --- |
| kagent UI | `http://localhost:18080` | `kubectl port-forward service/kagent-ui 18080:8080 -n kagent` |
| ArgoCD | `https://localhost:18081` | `kubectl port-forward service/argocd-server 18081:443 -n argocd` when installed |
| KPI Dashboard | `http://localhost:18082/kpi-dashboard.html` | `python -m http.server 18082 --directory out` |

Startup is idempotent. A live PID is reused; a stale PID is removed and the
process is restarted. A port conflict or early process exit is an error for
required dashboards. ArgoCD is optional: absence is reported as `SKIP`, while
a broken installed ArgoCD service is reported as `ERROR`.

`scripts/stop-judge-demo.sh` terminates only processes recorded in the runtime
directory and removes their PID files. It does not delete Azure resources.

## Azure Portal Links

The summary constructs tenant-safe Portal deep links using the current
subscription ID and URL-encoded Azure resource IDs. It prints links for:

- Microsoft Sentinel on `dah-data-law`;
- Log Analytics workspace logs;
- Azure OpenAI account;
- sim, SOC, and red AKS clusters;
- red ACR;
- red artifact Storage account.

Portal URLs are presentation conveniences. Resource existence and
provisioning state are verified with Azure CLI before a link is marked
`READY`.

## Runtime Verification

The launcher does not report success merely because deployment commands exit
zero. It requires:

- all five ARM deployments to be `Succeeded`;
- sim, SOC, and red AKS to be `Succeeded` and `Running`;
- all red nodes to be `Ready`;
- all kagent and `fried-pollack` Deployments to be Available;
- the Agent `Ready=True`;
- the RemoteMCPServer `Accepted=True`;
- `run_engagement` in the discovered MCP tools;
- successful HTTP responses from kagent UI and the KPI dashboard.

ArgoCD readiness is checked only when its service exists.

## Error Handling and Security

The launcher uses fail-fast shell behavior and never prints AOAI keys or
Kubernetes credentials. Secrets remain in Kubernetes Secret objects generated
by the existing bootstrap script. Kubeconfig is stored inside the runtime
directory with user-only permissions and converted to Azure CLI authentication
for non-interactive use.

Every failed stage prints the relevant log path. Background processes are not
silently detached without PID tracking. The stop command is always printed
when at least one local process starts.

The launcher does not create public LoadBalancers or Ingress resources. All
dashboard access remains bound to localhost through port-forwarding or the
local static HTTP server.

## Tests

Shell tests will stub Azure CLI, Kubernetes, process, and HTTP commands to
verify:

- stable Portal URL construction;
- image build skip/build decisions;
- PID reuse and stale-PID recovery;
- required versus optional dashboard behavior;
- final summary labels and short/full demo guidance;
- stop-script ownership boundaries.

Static verification includes `bash -n`, Bicep compilation, and Markdown link
checks where available. Live verification runs the launcher against the
deployed lab and confirms every required URL and runtime condition before the
change is pushed.

## Documentation Changes

The infrastructure README will gain a prominent reviewer quick start with the
short/full comparison table, prerequisites, one-command invocation, example
output, runtime directory, and stop command.

The comparison will explicitly state that the short path demonstrates the
model-independent core contribution and therefore needs no API key. The full
path demonstrates the optional hosted-AI integration by running kagent against
the Azure OpenAI `gpt-4o-soc` deployment backed by `gpt-4o-mini`. Both paths run
the same deterministic safety and verification contract; adding the model does
not grant it veto, scope, or execution authority.

The application README and `deploy/JUDGE-DEPLOY.md` will point to the launcher
for the complete three-plane path while retaining the existing manual steps as
the detailed troubleshooting and reproduction reference. `demo.py` remains
the short, Azure-free narrative demo.

## Non-Goals

- Exposing dashboards publicly on the internet.
- Replacing the existing detailed judge guide.
- Automatically deleting billable Azure resources.
- Claiming the local SOC contract emulator is a live Sentinel deployment.
- Installing ArgoCD unless explicitly enabled by the existing deployment flow.
