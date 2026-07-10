# Full Judge Demo Redeploy Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a guarded full-lab teardown, delete the current lab through that command, and cleanly redeploy the complete judge demo with ArgoCD and four verified dashboards.

**Architecture:** Extend the existing judge-demo process library and launcher rather than duplicating deployment logic. Add a fixed-allowlist teardown script with plan-only default and explicit subscription confirmation. Start the sibling `pollack-ai` FastAPI dashboard as a locally detached process and make ArgoCD a default required component of the full launcher.

**Tech Stack:** Bash, Azure CLI, Bicep, AKS, kubectl, kubelogin, Helm, FastAPI/Uvicorn, Python, pytest

## Global Constraints

- Live deletion is authorized only for `dah-data-rg`, `dah-soc-rg`, `dah-sim-rg`, `dah-red-rg`, and node resource groups discovered from their three AKS clusters.
- Actual deletion requires `--execute --subscription <active-subscription-id>`.
- Prefix wildcards must never select resource groups for deletion.
- ArgoCD is installed by default; `INSTALL_ARGOCD=false` is the explicit opt-out.
- All four dashboards bind only to `127.0.0.1`.
- Preserve unrelated `../pollack-ai/.claude/settings.local.json`.
- Do not add the wording the user explicitly rejected.

---

### Task 1: TDD the guarded teardown command

**Files:**
- Create: `scripts/destroy-all.sh`
- Create: `scripts/tests/destroy-all-test.sh`

**Interfaces:**
- Consumes: `--execute`, `--subscription`, optional `AZ_BIN`, and the current Azure CLI context.
- Produces: plan-only output or deletion of the four fixed groups plus AKS-discovered node groups.

- [ ] **Step 1: Write a stub-Azure failing test covering default plan mode, exact four-group allowlist, no wildcard selection, missing `--subscription`, subscription mismatch, missing-group no-op, and successful execute flow.**

```bash
output="$(AZ_BIN="$stub_az" bash scripts/destroy-all.sh)"
assert_contains "$output" "PLAN ONLY"
assert_not_contains "$(<"$calls")" "group delete"

if AZ_BIN="$stub_az" bash scripts/destroy-all.sh --execute --subscription wrong; then
  fail "subscription mismatch was accepted"
fi
```

- [ ] **Step 2: Run `bash scripts/tests/destroy-all-test.sh`; expect failure because the command does not exist.**

- [ ] **Step 3: Implement argument parsing, active-subscription equality, fixed group array, node-group discovery from AKS, local-dashboard stop, no-wait deletion submission, and bounded existence polling.**

- [ ] **Step 4: Run teardown tests and `bash -n scripts/destroy-all.sh`; require exit code 0.**

### Task 2: TDD the staff dashboard and default ArgoCD lifecycle

**Files:**
- Modify: `scripts/deploy-judge-demo.sh`
- Modify: `scripts/stop-judge-demo.sh`
- Modify: `scripts/tests/judge-demo-test.sh`

**Interfaces:**
- Consumes: `SOC_REPO` defaulting to `../pollack-ai`, and `INSTALL_ARGOCD` defaulting to `true`.
- Produces: `cyber-staff-dashboard` on port 18083 and required ArgoCD on port 18081.

- [ ] **Step 1: Add failing tests requiring `SOC_REPO`, default ArgoCD installation, `uvicorn app.dashboard:app --host 127.0.0.1 --port 18083`, the fourth PID owner, and all four summary URLs.**

- [ ] **Step 2: Run `bash scripts/tests/judge-demo-test.sh`; expect focused failures for the missing staff-dashboard and ArgoCD-default behavior.**

- [ ] **Step 3: Validate the sibling SOC checkout and Python imports, start its FastAPI dashboard through `start_owned_process`, verify title content, and add it to the summary.**

- [ ] **Step 4: Change ArgoCD default to true, pass both ACR name and login server to bootstrap, require its rollouts and HTTPS response, and keep explicit false as SKIP.**

- [ ] **Step 5: Extend `stop-judge-demo.sh` to own the staff-dashboard PID and rerun shell tests plus syntax checks.**

### Task 3: Update reviewer documentation

**Files:**
- Modify: `README.md`
- Modify: `../fried-pollack-ai/deploy/JUDGE-DEPLOY.md`

**Interfaces:**
- Consumes: final command names and ports.
- Produces: exact four-dashboard, default-ArgoCD, `SOC_REPO`, and guarded teardown instructions.

- [ ] **Step 1: Add the cyber staff dashboard at `http://localhost:18083`, change ArgoCD from optional to default, and list the three required sibling repositories.**

- [ ] **Step 2: Replace manual-delete guidance with plan-only and confirmed-execute `destroy-all.sh` examples.**

- [ ] **Step 3: Update the judge guide with matching commands and verify the rejected wording is absent.**

### Task 4: Execute the guarded live teardown and clean redeployment

**Files:**
- Execute: `scripts/destroy-all.sh`
- Execute: `scripts/deploy-judge-demo.sh`

**Interfaces:**
- Consumes: active subscription `b7acdba2-f2d6-4ff5-a059-008b20432f79` and current lab resources.
- Produces: an empty lab followed by a clean full deployment.

- [ ] **Step 1: Run the destroy command without arguments and capture the plan; verify the exact target set before deletion.**

- [ ] **Step 2: Run `bash scripts/destroy-all.sh --execute --subscription b7acdba2-f2d6-4ff5-a059-008b20432f79`; retain the log and require every authorized group to become absent.**

- [ ] **Step 3: Query the subscription and prove no fixed or discovered lab group remains.**

- [ ] **Step 4: Run `bash scripts/deploy-judge-demo.sh`; retain the full log and require ArgoCD plus all four dashboards READY.**

- [ ] **Step 5: Re-query ARM, AKS, nodes, kagent, Agent, RemoteMCPServer, MCP tools, ArgoCD, and all dashboard URLs.**

### Task 5: Final tests, commit, and push

**Files:**
- Verify and commit all task-owned files in `pollack-infra` and `fried-pollack-ai`.

**Interfaces:**
- Consumes: the clean redeployment and both working trees.
- Produces: passing tests and matching local/remote `main` tips.

- [ ] **Step 1: Run all infra shell tests, syntax checks, Bicep builds, and diff checks.**

- [ ] **Step 2: Run `pytest -q tests/test_deploy_manifests.py` and `./run_tests.sh` in `fried-pollack-ai`.**

- [ ] **Step 3: Review diffs, preserve unrelated files, commit task-owned documentation separately from infra runtime changes, and push without force.**

- [ ] **Step 4: Confirm remote tips, clean working trees, live URLs, and final Azure/Kubernetes states.**
