# Pollack: Field manual as Code with AI for UAV

<p align="center">
<img src="https://img.shields.io/badge/Azure-IaC-0078D4?logo=microsoftazure&logoColor=white" alt="Azure">
<img src="https://img.shields.io/badge/Bicep-subscription--scope-00BCF2?logo=azuredevops&logoColor=white" alt="Bicep">
<img src="https://img.shields.io/badge/AKS-Kubernetes-326CE5?logo=kubernetes&logoColor=white" alt="AKS">
<img src="https://img.shields.io/badge/Microsoft%20Sentinel-SIEM%2FSOAR-0078D4?logo=microsoft&logoColor=white" alt="Sentinel">
<img src="https://img.shields.io/badge/LangGraph-state%20machine-1C3C3C?logo=langchain&logoColor=white" alt="LangGraph">
</p>

![Pollack Red and Blue Teams](images/pollack-red-blue-team.png)

Pollack is an Azure infrastructure repository for a UAV cyber range that runs
offensive and defensive AI agents in a controlled closed loop. The design keeps
mission authority outside the model: policy, deterministic gates, and human-in-
the-loop approval control irreversible actions.

## Repository Scope

- Azure subscription-scope Bicep infrastructure
- AKS, Azure OpenAI, Microsoft Sentinel, and supporting data planes
- Integration seams for the UAV simulator, red-team agent, and defensive SOC agent

## Visual Overview

### Cyber Operations Staff Dashboard

![Cyber Operations Staff Dashboard](images/fig-cyber-staff-dashboard.png)

### SOC Detection Coverage KPI Dashboard

![SOC Detection Coverage KPI Dashboard](images/fig-kpi-dashboard.png)

## Demo

Choose the local demo when Azure access is unavailable, or run the full
three-plane deployment when infrastructure isolation must be demonstrated.

### Local demo

```bash
git clone https://github.com/s1ns3nz0/fried-pollack-ai.git
cd fried-pollack-ai
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
python demo.py
python run.py --emit-soc
python -m redteam_core.kpi.dashboard
```

### Azure full deployment

```bash
git clone https://github.com/s1ns3nz0/pollack-infra.git
git clone https://github.com/s1ns3nz0/fried-pollack-ai.git
cd pollack-infra
bash scripts/deploy-judge-demo.sh
```

The full demo creates billable Azure resources. Remove the resource group after
the demo and see `fried-pollack-ai/deploy/JUDGE-DEPLOY.md` for the full runbook.

```bash
scripts/deploy-all.sh
```

See [README.md](README.md) for the Korean project overview and the complete
field-manual-to-code mapping.
