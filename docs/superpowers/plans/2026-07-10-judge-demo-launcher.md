# Judge Demo Launcher Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Provide one reviewer command that deploys the full Azure lab, bootstraps the red workload, starts verified local dashboards, and prints local plus Azure Portal links with clear short-demo/full-deployment guidance.

**Architecture:** Keep `deploy-all.sh` as the infrastructure primitive and add a thin `deploy-judge-demo.sh` orchestrator. Put reusable URL, process, and readiness behavior in a sourceable shell library with stub-driven tests; keep stop behavior in a separate command. The launcher composes the sibling `fried-pollack-ai` bootstrap and dashboard generator without exposing any dashboard publicly.

**Tech Stack:** Bash, Azure CLI, Azure Bicep, AKS, kubectl, kubelogin, Helm, Python HTTP server, pytest

## Global Constraints

- The short demo requires no hosted AI model and must remain runnable without Azure.
- The full demo uses Azure OpenAI `gpt-4o-mini` through deployment `gpt-4o-soc` only for kagent interaction, reasoning, and summarization.
- Scope enforcement, safety gates, HITL routing, execution policy, and ground-truth validation remain deterministic in both paths.
- Dashboard listeners bind to `127.0.0.1`; no public LoadBalancer or Ingress is created.
- Runtime PID, kubeconfig, and log files live under `/tmp/fried-pollack-judge-demo/` by default.
- The launcher never prints AOAI keys, kubeconfig contents, or Kubernetes Secret values.
- The launcher never deletes Azure resources.
- Required dashboards fail the run when unavailable; absent ArgoCD is reported as `SKIP`.

---

### Task 1: Test and implement reviewer URL helpers

**Files:**
- Create: `scripts/lib/judge-demo.sh`
- Create: `scripts/tests/judge-demo-test.sh`

**Interfaces:**
- Produces: `portal_resource_url TENANT_ID RESOURCE_ID`, `sentinel_portal_url TENANT_ID WORKSPACE_ID`, `print_demo_comparison`, and `print_portal_links`.
- Consumes: plain tenant/resource identifiers; the pure URL helpers do not call Azure.

- [ ] **Step 1: Write failing shell assertions for resource overview links, Sentinel links, and comparison copy.**

```bash
assert_eq \
  "https://portal.azure.com/#@tenant-id/resource/subscriptions/sub/resourceGroups/rg/providers/Microsoft.ContainerService/managedClusters/aks/overview" \
  "$(portal_resource_url tenant-id /subscriptions/sub/resourceGroups/rg/providers/Microsoft.ContainerService/managedClusters/aks)"

comparison="$(print_demo_comparison)"
assert_contains "$comparison" "Short local demo"
assert_contains "$comparison" "No hosted model"
assert_contains "$comparison" "gpt-4o-mini"
assert_contains "$comparison" "deterministic"
```

- [ ] **Step 2: Run `bash scripts/tests/judge-demo-test.sh`; expect failure because `scripts/lib/judge-demo.sh` does not exist.**

- [ ] **Step 3: Implement the pure URL and comparison helpers, including stable labels for Sentinel, Log Analytics, AOAI, three AKS clusters, ACR, and Storage.**

- [ ] **Step 4: Run `bash scripts/tests/judge-demo-test.sh`; expect the URL and comparison assertions to pass.**

### Task 2: Test and implement owned background-process management

**Files:**
- Modify: `scripts/lib/judge-demo.sh`
- Modify: `scripts/tests/judge-demo-test.sh`
- Create: `scripts/stop-judge-demo.sh`

**Interfaces:**
- Produces: `pid_is_live PID_FILE`, `start_owned_process NAME LOG_FILE COMMAND...`, `wait_for_http URL ALLOW_INSECURE TIMEOUT_SECONDS`, and `stop_owned_process NAME`.
- Consumes: `JUDGE_DEMO_RUNTIME_DIR`, defaulting to `/tmp/fried-pollack-judge-demo`.

- [ ] **Step 1: Add failing tests using temporary directories and stub processes for live-PID reuse, stale-PID replacement, required HTTP timeout, and stop ownership.**

```bash
JUDGE_DEMO_RUNTIME_DIR="$tmp/runtime"
start_owned_process sample "$tmp/sample.log" sh -c 'sleep 30'
first_pid="$(<"$JUDGE_DEMO_RUNTIME_DIR/sample.pid")"
start_owned_process sample "$tmp/sample.log" sh -c 'sleep 30'
assert_eq "$first_pid" "$(<"$JUDGE_DEMO_RUNTIME_DIR/sample.pid")"
stop_owned_process sample
if kill -0 "$first_pid" 2>/dev/null; then fail "owned process survived stop"; fi
```

- [ ] **Step 2: Run the focused process tests; expect failure because the functions and stop command are missing.**

- [ ] **Step 3: Implement PID validation with `kill -0`, stale-file cleanup, localhost background startup, log redirection, and process-exit detection.**

- [ ] **Step 4: Implement `stop-judge-demo.sh` by sourcing the library and stopping only the named `kagent-ui`, `argocd`, and `kpi-dashboard` processes recorded in the runtime directory.**

- [ ] **Step 5: Run `bash scripts/tests/judge-demo-test.sh` and `bash -n scripts/lib/judge-demo.sh scripts/stop-judge-demo.sh`; expect exit code 0 and no surviving test processes.**

### Task 3: Test and implement the one-command launcher

**Files:**
- Create: `scripts/deploy-judge-demo.sh`
- Modify: `scripts/lib/judge-demo.sh`
- Modify: `scripts/tests/judge-demo-test.sh`

**Interfaces:**
- Consumes: `APP_REPO`, `JUDGE_DEMO_RUNTIME_DIR`, `TOOLSERVER_TAG`, `INSTALL_ARGOCD`, and existing `deploy-all.sh` plus app bootstrap scripts.
- Produces: a complete judge-ready deployment and stable `[JUDGE DEMO READY]` summary.

- [ ] **Step 1: Add a dry-run/stubbed launcher test that records command order and requires deploy-all → resource discovery → conditional ACR build → app bootstrap → KPI generation → local services → readiness verification → summary.**

```bash
expected=(deploy-all discover build-image bootstrap generate-kpi start-dashboards verify print-summary)
assert_eq "${expected[*]}" "$(paste -sd' ' "$COMMAND_LOG")"
```

- [ ] **Step 2: Run the launcher test; expect failure because `scripts/deploy-judge-demo.sh` does not exist.**

- [ ] **Step 3: Implement prerequisite checks for `az`, `kubectl`, `kubelogin`, `helm`, `curl`, and `python`, plus sibling app-repository validation.**

- [ ] **Step 4: Run `deploy-all.sh`, query its ARM outputs and resource IDs, create a user-only red kubeconfig, and export the exact variables consumed by `bootstrap-red-agent.sh`.**

- [ ] **Step 5: Check `az acr repository show-tags`; run `az acr build` only when `${TOOLSERVER_TAG}` is absent, then invoke the app bootstrap with the immutable image reference.**

- [ ] **Step 6: Generate KPI HTML, start kagent and KPI listeners on `127.0.0.1:18080` and `127.0.0.1:18082`, and optionally install/start ArgoCD on `127.0.0.1:18081` when `INSTALL_ARGOCD=true`.**

- [ ] **Step 7: Require ARM success, AKS running state, node readiness, Deployment availability, Agent Ready, RemoteMCPServer Accepted, `run_engagement` discovery, and HTTP readiness before printing success.**

- [ ] **Step 8: Print local URLs, verified Azure Portal links, AI-model role, runtime evidence, log paths, and `bash scripts/stop-judge-demo.sh`.**

- [ ] **Step 9: Run `bash scripts/tests/judge-demo-test.sh` and `bash -n scripts/deploy-judge-demo.sh scripts/lib/judge-demo.sh scripts/stop-judge-demo.sh`; expect exit code 0.**

### Task 4: Add the reviewer quick start and model comparison

**Files:**
- Modify: `README.md`
- Modify: `../fried-pollack-ai/README.md`
- Modify: `../fried-pollack-ai/deploy/JUDGE-DEPLOY.md`

**Interfaces:**
- Consumes: the launcher command and stable output labels from Task 3.
- Produces: consistent reviewer instructions in both repositories.

- [ ] **Step 1: Add a prominent infrastructure README section before the long architecture narrative with a comparison table covering time, cost, prerequisites, AI model, model authority, SOC evidence, isolation evidence, dashboards, and limitations.**

- [ ] **Step 2: Add the exact clone layout, prerequisites, `bash scripts/deploy-judge-demo.sh`, local URLs, Portal-link categories, runtime directory, stop command, and teardown warning.**

- [ ] **Step 3: Add a concise reviewer callout to the app README: `python demo.py` for the hosted-model-free short path and the infra launcher for the Azure `gpt-4o-mini` path.**

- [ ] **Step 4: Update `deploy/JUDGE-DEPLOY.md` so Tier 0 remains the recommended fast reproduction, Tier 1 remains the cheaper manual red-only path, and Full 3-plane points to the launcher plus the existing detailed reference.**

- [ ] **Step 5: Search all changed documentation for contradictory statements such as calling Tier 0 live Sentinel or granting the LLM execution authority; fix every mismatch.**

### Task 5: Run static, unit, and live judge-demo verification

**Files:**
- Verify: all changed scripts and documentation
- Verify: live resources under the current Azure subscription

**Interfaces:**
- Consumes: the currently deployed lab and both repositories.
- Produces: fresh evidence that the launcher is repeatable and its URLs are usable.

- [ ] **Step 1: Run `bash scripts/tests/quota-test.sh`, `bash scripts/tests/judge-demo-test.sh`, `bash -n scripts/**/*.sh`, Bicep builds, and `git diff --check`; require exit code 0.**

- [ ] **Step 2: Run app deployment tests with `pytest -q tests/test_deploy_manifests.py` and the full app suite with `./run_tests.sh`; require zero failures.**

- [ ] **Step 3: Run `bash scripts/deploy-judge-demo.sh` against the existing idempotent deployment and retain its full log.**

- [ ] **Step 4: Fetch each printed localhost URL with `curl`, query every linked Azure resource, and require the advertised Kubernetes/MCP states.**

- [ ] **Step 5: Re-run the launcher and require PID reuse plus image-build skip; run the stop command and require all owned listeners to terminate.**

### Task 6: Commit and push both repositories

**Files:**
- Commit in `pollack-infra`: launcher, library, tests, README, spec, and plan
- Commit in `fried-pollack-ai`: README and judge guide

**Interfaces:**
- Consumes: clean verification evidence and task-owned diffs.
- Produces: updated `origin/main` branches with matching local and remote tips.

- [ ] **Step 1: Review both working trees with `git status`, `git diff`, and `git diff --check`; stage only task-owned files.**

- [ ] **Step 2: Commit the app documentation separately from the infrastructure launcher implementation.**

- [ ] **Step 3: Fetch each remote, rebase only when required for a fast-forward push, and rerun affected verification after any rebase.**

- [ ] **Step 4: Push both `main` branches without force and confirm `git rev-parse HEAD` equals `git ls-remote origin refs/heads/main`.**

- [ ] **Step 5: Report exact commit IDs, test counts, live URLs, Azure states, MCP evidence, and whether ArgoCD was READY or SKIP.**
