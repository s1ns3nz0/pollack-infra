# Quota-Aware Lab Deployment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fit the complete lab topology inside the current 20-vCPU Korea Central quota, deploy every plane, and verify the infrastructure and red workload end to end.

**Architecture:** Parameterize red AKS pool sizing, select a one-node SOC and two D2 red nodes for the lab profile, and add a small shell quota library that validates the desired topology and waits for quota released by the SOC scale-down. Keep the existing deployment order and preserve all existing simulation scheduling boundaries.

**Tech Stack:** Azure Bicep, Azure CLI, Bash, AKS, kubectl, Helm, pytest

## Global Constraints

- Keep the existing three-pool simulation topology unchanged at three `Standard_D4s_v5` nodes.
- Configure SOC as one `Standard_D4s_v5` node for this lab profile.
- Configure red as one `Standard_D2s_v5` system node plus one `Standard_D2s_v5` workload node.
- Never delete or recreate an existing cluster automatically.
- Preserve the existing uncommitted `bicep/planes/aoai.bicep` change.
- Do not push until infrastructure deployment and all applicable internal tests pass.

---

### Task 1: Test quota calculations and bounded polling

**Files:**
- Create: `scripts/lib/quota.sh`
- Create: `scripts/tests/quota-test.sh`

**Interfaces:**
- Produces: `vm_size_vcpus SIZE`, `topology_vcpus SIM_SIZE SIM_COUNT SOC_SIZE SOC_COUNT RED_SYSTEM_SIZE RED_SYSTEM_COUNT RED_USER_SIZE RED_USER_COUNT`, and `wait_for_regional_vcpu_capacity LOCATION REQUIRED_FREE TIMEOUT_SECONDS POLL_SECONDS`.
- Consumes: Azure CLI `az vm list-usage` only from `wait_for_regional_vcpu_capacity`; calculation functions remain pure.

- [ ] **Step 1: Write executable shell assertions that expect D2/D4 mappings, the 20-vCPU lab total, rejection of unknown sizes, and bounded polling behavior with a stubbed `az` function.**

```bash
assert_eq 2 "$(vm_size_vcpus Standard_D2s_v5)"
assert_eq 4 "$(vm_size_vcpus Standard_D4s_v5)"
assert_eq 20 "$(topology_vcpus Standard_D4s_v5 3 Standard_D4s_v5 1 Standard_D2s_v5 1 Standard_D2s_v5 1)"
if vm_size_vcpus Standard_Unknown >/dev/null 2>&1; then exit 1; fi
```

- [ ] **Step 2: Run `bash scripts/tests/quota-test.sh`; expect failure because `scripts/lib/quota.sh` does not exist.**

- [ ] **Step 3: Implement the three quota functions with integer validation, `name.value == 'cores'` usage lookup, clear stderr diagnostics, and timeout return code 1.**

- [ ] **Step 4: Run `bash scripts/tests/quota-test.sh`; expect all assertions to pass with exit code 0.**

- [ ] **Step 5: Run `bash -n scripts/lib/quota.sh scripts/tests/quota-test.sh`; expect exit code 0.**

### Task 2: Parameterize the red AKS lab footprint

**Files:**
- Modify: `bicep/modules/aks-red.bicep`
- Modify: `bicep/main.bicep`
- Modify: `bicep/params/lab.bicepparam`

**Interfaces:**
- Produces: subscription parameters `redSystemNodeSize`, `redSystemNodeCount`, `redUserNodeSize`, and `redUserNodeCount`.
- Consumes: those parameters in the `red-aks` module and applies them to the two agent pool profiles.

- [ ] **Step 1: Add size parameters and integer count parameters constrained to 1–5 in `aks-red.bicep`, then replace both hard-coded sizes and counts.**

```bicep
param systemNodeSize string = 'Standard_D4s_v5'
@minValue(1)
@maxValue(5)
param systemNodeCount int = 1
param userNodeSize string = 'Standard_D4s_v5'
@minValue(1)
@maxValue(5)
param userNodeCount int = 1
```

- [ ] **Step 2: Expose matching red-prefixed parameters in `main.bicep` and forward them to the `aks` module.**

- [ ] **Step 3: Set both lab node sizes to `Standard_D2s_v5` and both counts to one in `lab.bicepparam`.**

- [ ] **Step 4: Run `az bicep build --file bicep/main.bicep --stdout >/dev/null`; expect exit code 0.**

- [ ] **Step 5: Run `az deployment sub validate --location koreacentral --template-file bicep/main.bicep --parameters bicep/params/lab.bicepparam`; accept only a successful validation result.**

### Task 3: Make the full-stack script quota-aware

**Files:**
- Modify: `scripts/deploy-all.sh`
- Test: `scripts/tests/quota-test.sh`

**Interfaces:**
- Consumes: quota functions from `scripts/lib/quota.sh` and environment overrides `SIM_NODE_SIZE`, `SIM_NODE_COUNT`, `SOC_NODE_SIZE`, `SOC_NODE_COUNT`, `RED_SYSTEM_NODE_SIZE`, `RED_SYSTEM_NODE_COUNT`, `RED_USER_NODE_SIZE`, `RED_USER_NODE_COUNT`, `QUOTA_WAIT_TIMEOUT`, and `QUOTA_POLL_SECONDS`.
- Produces: an idempotent deployment run that converges SOC before waiting for four free regional vCPUs and submitting red.

- [ ] **Step 1: Source the quota library relative to the script path and define the lab topology defaults.**

- [ ] **Step 2: Compute the desired topology total and compare it with the regional `cores` limit before any AKS deployment; fail with desired and limit values when it cannot fit.**

- [ ] **Step 3: Pass explicit simulation sizes/counts and `systemNodeCount=1`/SOC size to their resource-group deployments.**

- [ ] **Step 4: After SOC succeeds, call `wait_for_regional_vcpu_capacity` for the red footprint, then pass the red sizing overrides to the subscription deployment.**

- [ ] **Step 5: Run `bash -n scripts/deploy-all.sh` and `bash scripts/tests/quota-test.sh`; expect both to exit 0.**

### Task 4: Validate and deploy all Azure planes

**Files:**
- Verify: all `bicep/**/*.bicep`, `bicep/params/lab.bicepparam`, and `scripts/deploy-all.sh`

**Interfaces:**
- Consumes: current Azure subscription and the existing data, AOAI, sim, SOC, and partially created red resources.
- Produces: successful `data-mvp`, `aoai-mvp`, `sim-aks`, `soc-mvp`, and subscription `main` deployments.

- [ ] **Step 1: Run Bicep builds for each entry-point template and run `git diff --check`; expect exit code 0.**

- [ ] **Step 2: Run `scripts/deploy-all.sh` and retain the complete log; expect `== done. all planes provisioned. ==`.**

- [ ] **Step 3: If ARM fails, inspect the exact failed deployment operation, make the smallest in-scope correction, rerun static verification, and resume the idempotent deployment.**

- [ ] **Step 4: Query all deployment states and require `Succeeded`; query all AKS clusters and require `Succeeded` plus `Running`.**

- [ ] **Step 5: Verify pool topology: sim has three D4 nodes, SOC has one D4 node, and red has one D2 system plus one D2 workload node.**

### Task 5: Verify Kubernetes and red-plane integrations

**Files:**
- Verify: Azure resources and live AKS clusters
- Use: `../fried-pollack-ai/scripts/bootstrap-red-agent.sh`

**Interfaces:**
- Consumes: live sim, SOC, and red clusters plus deployed AOAI, ACR, firewall, storage, identities, and role assignments.
- Produces: ready Kubernetes nodes and a deployed red-agent workload on `dah-red-aks` only.

- [ ] **Step 1: Fetch each kubeconfig into a separate temporary file and run `kubectl get nodes`; require every node to be `Ready`.**

- [ ] **Step 2: Verify red route-table/firewall association, firewall provisioning, ACR and storage availability, managed identities, federated credentials, and OpenAI role assignment with Azure CLI queries.**

- [ ] **Step 3: Run the red-agent bootstrap from `fried-pollack-ai` with the red kubeconfig and deployed AOAI values; require Helm and Kubernetes rollout commands to succeed.**

- [ ] **Step 4: Require the ToolServer deployment rollout and all relevant kagent/red-agent pods to become Ready; collect events and logs for any failure and apply only in-scope corrections.**

- [ ] **Step 5: Confirm no red-agent, kagent, or ToolServer workloads exist on `dah-sim-aks`.**

### Task 6: Run internal tests, commit, and push

**Files:**
- Verify: `../fried-pollack-ai/run_tests.sh`
- Modify only if a deployment-specific defect is discovered: relevant deployment files in `../fried-pollack-ai`

**Interfaces:**
- Consumes: completed live deployment and both repository working trees.
- Produces: fresh test evidence, focused commits, and updated `origin/main` branches.

- [ ] **Step 1: Run `./run_tests.sh` from `fried-pollack-ai`; require exit code 0 and zero failures.**

- [ ] **Step 2: Run deployment manifest tests explicitly with `pytest -q tests/test_deploy_manifests.py`; require exit code 0.**

- [ ] **Step 3: Re-run infrastructure static checks and live Azure/Kubernetes readiness checks after the last correction.**

- [ ] **Step 4: Review `git diff`, `git diff --check`, and both repository statuses; preserve unrelated user changes and stage only task-owned files.**

- [ ] **Step 5: Commit implementation changes with focused messages, then push the applicable `main` branches to their configured origins.**

- [ ] **Step 6: Confirm local HEAD equals the remote branch tip and report the exact test, deployment, cluster, and push evidence.**
