# pollack: UAV 사이버 레인지와 폐루프 AI 교전 시스템 / UAV Cyber Range and Closed-Loop AI Engagement System

![Azure](https://img.shields.io/badge/Azure-IaC-0078D4?logo=microsoftazure&logoColor=white)
![Bicep](https://img.shields.io/badge/Bicep-subscription--scope-00BCF2?logo=azuredevops&logoColor=white)
![AKS](https://img.shields.io/badge/AKS-Kubernetes-326CE5?logo=kubernetes&logoColor=white)
![Sentinel](https://img.shields.io/badge/Microsoft%20Sentinel-SIEM%2FSOAR-0078D4?logo=microsoft&logoColor=white)
![LangGraph](https://img.shields.io/badge/LangGraph-state%20machine-1C3C3C?logo=langchain&logoColor=white)
![RAG](https://img.shields.io/badge/RAG-RAGFlow%2FGraphRAG-4B8BBE)
![Python](https://img.shields.io/badge/Python-3.11-3776AB?logo=python&logoColor=white)
![Doctrine](https://img.shields.io/badge/doctrine-JP%2FCJCSI%2FDoDD-556B2F)
![NIST](https://img.shields.io/badge/NIST-800--53%2F61%2FAI%20RMF-005288)
![Loop](https://img.shields.io/badge/OCO%E2%86%94DCO-closed%20loop-e11d48)
![Region](https://img.shields.io/badge/region-Korea%20Central%2FSouth-0078D4)

**pollack** 은 KUS-FS급 MUAV 임무 시스템을 대상으로 **공격 AI ↔ 방어 AI를 하나의
폐루프로 돌리는** UAV 사이버 레인지다. 이 저장소(`pollack-infra`)는 그 레인지를
띄우는 Azure 인프라(IaC)와 평면 사이 이음새를 소유한다.

## Field Manual as Code / 설계 원칙

설계의 출발점을 모델이 아니라 **조직과 교리**에 두었다. 핵심 원칙은 한 문장이다 —
**"AI는 판단을 돕고, 권한은 코드와 정책이 쥔다."** AI는 참모이고, 방아쇠는 사람과
코드가 쥔다. LLM은 계획 보조·결과 요약·근거 정리처럼 불확실성을 줄이는 일을 맡고,
교전권한·물리 비가역 명령 승인·심각도 하한·정탐 판정·대응 실행 여부처럼 임무 안전과
법적 책임이 걸린 결정은 **결정론 모듈과 HITL 게이트**가 처리한다.

미군 기준을 빌린 건 권위 차용이 아니라 이미 검증된 절차서를 재사용한 것이다. 작전
논리는 미군 교리(JP·CJCSI·DoDD)에서, 사고대응·증거·통제 원칙은 NIST(SP 800-53·
800-61·800-184·800-160v2·OSCAL·AI RMF)에서, 실행 자동화는 CNCF 클라우드 네이티브
스택과 LangGraph에서 가져왔다.

**조직 분리가 첫 설계 결정.** USCYBERCOM 사이버임무군(CMF)은 공세 전력(OCO —
NMT·CNMF·CMT)과 방어 전력(DCO-IDM — CPT)을 애초에 나눈다. 이 공수 분리를 그대로
가져와 공격 `fried-pollack-ai`와 방어 `pollack-ai`를 별도 저장소·별도 런타임으로
쪼갰다. 방어측은 레드 코드를 import하지 않고 두 에이전트는 UAV*_CL 텔레메트리
스키마로만 만난다 — 공격자가 방어측 답안지를 커닝해 회피에 최적화되는 경로를 원천
차단한다.

### Field Manual as Code 매핑 / Doctrine-to-Code Mapping

| 교범·조직 근거 | 코드 구현 |
|---|---|
| JP 3-12 · OCO/DCO/DODIN 분리 | 저장소 분리, UAV*_CL one-way 브릿지 |
| JP 3-60 · 표적화(CARVER·HPTL) | red `planner`, `targeting/carver.py`·`prioritize.py` |
| F3EAD 순환 | red 그래프 노드 순서(recon→…→reporter) |
| SROE·CDE·PID·JCEOI | `checker`·`broker`·`roe_gate.py`·`engagement/gate.py` |
| DoDD 3000.09 · 인간판단·중지 | HITL interrupt, 단발 토큰, out-of-band 검증 |
| CPT · Detect~Assess 순환 | blue 6-에이전트 SOC 그래프 |

### 설계 보고서 요약 / Design Report Summary

1. **공격 시나리오 설계** — `uav-sim-env` 자산을 xT-STRIDE로 위협 모델링하고 ATT&CK for UAV로 정규화해, 직교하는 3대 시나리오(제어권 탈취·영상 변조·데이터 유출)를 뽑는다.
2. **방어 아키텍처** — 탐지룰·Golden Fixture·Runbook·CACAO Playbook을 전술판 기준으로 미리 엮은 **사전 정의 계약**, D3FEND 매핑, 다층 방어, 공격 이후 임무 지속성(**Mission Assurance**)까지 세운다.
3. **AI 에이전트 설계** — 두 에이전트를 LangGraph 상태머신으로 구현하고, 권한(교전·승인·판정·배포)은 RoE·HITL·오라클로 **모델 밖**에 두며, RAG는 조사 보강에만 쓴다.
4. **결론·향후 계획** — 폐루프 적대 검증·결정론 권한 경계·Tier 0 재현성이 핵심 기여이고, 미커버 기법 실 배포와 Azure 라이브 배선이 다음 단계다.
5. **참고문헌** — 미군 교리(JP·CJCSI·DoDD)·NIST·MITRE·OASIS·학술(xT-STRIDE)에 근거를 둔다.

### AI 엔지니어링 계층 / AI Engineering Layers

임무 절차를 **타입이 정해진 상태머신**으로 만들고 그 안에 LLM을 제한된 부품으로
배치한다. 공정 라인처럼 각 계층이 한 가지 안전 역할만 맡는다.

| 계층 | 목적 | 구현 요소 |
|---|---|---|
| **Agent workflow** | 교리 절차를 상태 전이로 고정 | LangGraph, `SOCState`, red/blue 그래프 빌더 |
| **Tool boundary** | LLM의 직접 위험행위 차단 | FastMCP, kagent, coarse-grained MCP, allowlist |
| **Knowledge grounding** | 근거 검색은 허용, 판정권은 불허 | RAGFlow, 로컬 GraphRAG, `RetrievedChunk` |
| **Decision control** | 안전·법적 결정을 모델 밖으로 | `SeverityEngine`, signal judge, HITL, CACAO/런북 |
| **Evaluation & Ops** | 재현성·관측성·배포 무결성 | golden fixture, OpenTelemetry, Argo CD drift |

LLM은 다섯 계층 어디에서도 최종 권한을 갖지 않는다. `core/llm.py`의 `LLMClient`
프로토콜 뒤에 있으며, 현재 Ollama `qwen2.5`이고 Azure OpenAI(GPT-4o)는 같은
프로토콜을 구현하는 교체 지점으로 남겨 뒀다. **모델을 바꿔도 상태·정책·게이트
경계는 그대로다** — "모델은 교체 가능한 부품"의 실제 의미다.

### 폐루프 교전 구조 / Closed-Loop Engagement

두 에이전트는 **코드 파이프가 아니라 공유 스키마에서 닫힌다.** 공격이 킬체인을
실행하면 UAV*_CL 텔레메트리가 남고, 방어는 그 로그를 읽어 탐지·판정·대응하며,
막은 단계와 놓친 단계가 다음 교전의 입력이 된다(권투의 실제 스파링). 차단·거부된
액션은 로그를 남기지 않으므로 **방어가 어느 단계에서 킬체인을 끊었는지가 로그의
있고 없음만으로** 확인된다.

```mermaid
flowchart LR
  subgraph RED["🔴 OCO · fried-pollack-ai"]
    R1[recon] --> R2[plan/synth] --> R3[HITL+exec] --> R4[validate/report]
  end
  subgraph RANGE["🟡 격리 SITL/HIL 레인지"]
    U["uav-sim-env<br/>UAV*_CL telemetry"] --> S["Sentinel / sim_bridge"]
  end
  subgraph BLUE["🔵 DCO-IDM · pollack-ai"]
    B1[triage] --> B2[investigate+hunt] --> B3[validate+approve] --> B4[respond/report]
  end
  R4 -->|"--emit-soc"| U
  S --> B1
  B4 -->|"탐지·차단 결과"| U
  B4 -. "탐지공백·룰 후보" .-> R1
```

## 공격·방어 에이전트 / Offensive and Defensive Agents

| | 🔴 공격 (OCO) | 🔵 방어 (DCO-IDM) |
|---|---|---|
| 저장소 | [fried-pollack-ai](https://github.com/s1ns3nz0/fried-pollack-ai) | [pollack-ai](https://github.com/s1ns3nz0/pollack-ai) |
| 엔진 | LangGraph — recon→plan→HITL→exec→report | 6-에이전트 SOC 그래프 + 3 주기 워커 |
| 규모 | Python 197 모듈·원자 액션 22·무기고 23종·테스트 616 | investigation/report/response + 상관·킬웹·CACAO |
| 통제 | RoE 게이트·HITL·allowlist (모델 밖 결정론) | 정책 하한 + METT-TC 상승·HITL 강제·guardrail |
| 산출 | `UAV*_CL` 행 + SOC Alert | 탐지·차단·RTL·룰 후보 |

## SOC 탐지 커버리지 / SOC Detection Coverage

| 지표 | 값 |
|---|---|
| ATT&CK 전술 커버리지 | **93.3%** (15전술 중 14) |
| 기법 커버리지 | **80.0%** (110기법 중 88) |
| 탐지 룰 | **165** (`dah-sentinel-content`) |
| 무기고 커버(공격) | **100%** (23/23) |

## 저장소 구성 / Repository Map

| 저장소 | 계층 | 담는 것 |
|---|---|---|
| [**pollack-infra**](https://github.com/s1ns3nz0/pollack-infra) | infra | 이 저장소 — 세 평면 Azure IaC + 평면 이음새 |
| [uav-sim-env](https://github.com/s1ns3nz0/uav-sim-env) | sim | KUS-FS급 MUAV SITL 레인지 (ArduPilot·13 컨테이너·19 `UAV*_CL`) |
| [fried-pollack-ai](https://github.com/s1ns3nz0/fried-pollack-ai) | red | OCO 레드팀 에이전트 |
| [pollack-ai](https://github.com/s1ns3nz0/pollack-ai) | soc | DCO-IDM 방어 AI SOC |
| [dah-sentinel-content](https://github.com/s1ns3nz0/dah-sentinel-content) | soc | Sentinel Detection-as-Code — 분석 룰 167개(`S*` 131 + `C*` 34) |

## 설계 보고서 / Design Report

| # | 제목 | 요약 |
|---|---|---|
| **1** | 공격 시나리오 설계 | `uav-sim-env` 자산을 xT-STRIDE로 위협 모델링하고 MITRE ATT&CK for UAV(15전술·116기법)로 정규화. 직교하는 3대 시나리오 확정 — **A** 제어권 탈취 · **B** ISR 영상 변조 · **C** ISR 데이터 유출. |
| **2** | 방어 아키텍처 | 탐지룰·Golden Fixture·Runbook·CACAO Playbook을 전술판 기준으로 미리 엮은 **사전 정의 계약** + D3FEND 방어 매핑 + 다층 방어. 공격 이후 임무 지속성을 판정하는 **Mission Assurance**. |
| **3** | AI 에이전트 설계 | 두 에이전트를 LangGraph 상태머신으로 구현. **Field Manual as Code** — 미군 교리를 저장소 경계·그래프 순서·승인 게이트로 사상. RoE·단발 HITL 토큰·out-of-band 오라클로 권한을 모델 밖에, RAG는 조사 보강만. AI Engineering **다섯 계층**. |
| **4** | 결론 및 향후 계획 | 핵심 기여 — **폐루프 적대 검증**(defend forward)·**결정론 권한 경계 + HITL**·**Tier 0 재현성**. 향후 — 미커버·계획 기법을 실 배포로 커버 확대, Azure 라이브 배선(OpenAI·AKS CronJob·Sentinel 라이브 경로). |
| **5** | 참고문헌 | 미군 교리(JP·CJCSI·DoDD) · 표준(NIST·OASIS·OWASP) · 위협지식(MITRE ATT&CK/ATLAS/D3FEND·CISA) · 학술(xT-STRIDE) · 기술 스택 출처. |

## 실행 방법 / How to Run

### 1. 공격 에이전트 실행 / Run the Offensive Agent ([fried-pollack-ai](https://github.com/s1ns3nz0/fried-pollack-ai))

```bash
python run.py --emit-soc     # 킬체인 실행 + UAV*_CL·SOC Alert 산출
python run.py --hardened     # PoV 페어: 취약 인스턴스 성공 / 하드닝 인스턴스 거부 대조
```

`--emit-soc` 는 관측한 감사 이벤트를 `out/uav_cl_rows.ndjson`(UAV*_CL 행)과
`out/soc_alert.json`으로 내보낸다 — 이게 방어측 입력이다. `--hardened` 는 같은
공격을 서명(MAVLink2)·망분리·링크암호화로 거부해 "무방비 기체는 뚫리고 방비된
기체는 막힌다"를 나란히 보여 준다. **외부 의존 없이 표준 라이브러리만으로 Tier 0
재현**된다.

### 2. 방어 에이전트 실행 / Run the Defensive Agent ([pollack-ai](https://github.com/s1ns3nz0/pollack-ai))

같은 스키마의 텔레메트리를 Azure Sentinel 또는 `sim_bridge`로 읽어 6-에이전트
파이프라인(triage→investigation+hunt→validation+approval→response)을 돈다. LLM
요약은 로컬 Ollama(`qwen2.5`)로 실연동되며 결정론 폴백을 갖춘다. 탐지 룰은
[dah-sentinel-content](https://github.com/s1ns3nz0/dah-sentinel-content)의 165룰
라이브러리에서 온다.

### 3. Azure 인프라 배포 / Deploy Azure Infrastructure

레인지를 Azure에 올린다. 전체 스택을 의존순서로 배포한다.

```bash
scripts/deploy-all.sh    # data(SIEM) → aoai → sim → soc → red
```

red만 미리보기·배포하려면:

```bash
az deployment sub what-if --location koreacentral \
  --template-file bicep/main.bicep --parameters bicep/params/lab.bicepparam

scripts/deploy-red-with-sim.sh    # red (+ DEPLOY_SIM=true 시 sim 존재-시-건너뜀)
```

**자기 구독에 배포하는 리뷰어 (Path B):** `bicep/params/judge.bicepparam`를 복사해
`REPLACE_*` 토큰을 채우고 `RED_PARAM_FILE`로 스크립트에 물린다. sim 레인지는 RG-scope
(`bicep/planes/sim-aks.bicep`)로 `deploy-all.sh` 경유. 전체 런북은 red 앱 저장소의
`deploy/JUDGE-DEPLOY.md` 참고.

## 인프라 저장소 역할 / Infrastructure Repository Role

세 평면(🔴 red `dah-red-aks` / 🟡 sim `dah-sim-aks` / 🔵 soc `dah-soc-aks`)은 각각
독립된 AKS 클러스터·VNet·리소스 그룹이다. red는 살아있는 공격 도구를 돌리므로,
평면 경계는 **실제 신뢰경계**다. 어느 평면에도 속하지 않는 이음새가 여기 산다.

- red↔sim VNet 피어링 + Azure Firewall 이그레스 허용목록 (공격 경로)
- 공유 Sentinel / Log Analytics 워크스페이스 `dah-data-law` — sim은 append-only로
  쓰고 soc는 읽는다 (탐지 경로, sim↔soc 직접 피어링 **없음**)
- 프라이빗 DNS 존 (`*.pollack.store`) · 평면 경계를 강제하는 RBAC

```
bicep/
  main.bicep · modules/                    # red 평면 (subscription 범위) + 모듈
  planes/                                  # sim/soc/aoai/data (RG 범위, 라이브 canonical)
    data.bicep(dah-data-law+Sentinel) · aoai.bicep(gpt-4o-mini)
    sim-aks.bicep · sim-vm.bicep · soc.bicep
  params/                                  # lab · judge 파라미터
scripts/
  deploy-all.sh              # 전체 스택 의존순서(data→aoai→sim→soc→red)
  deploy-red-with-sim.sh     # red(+선택 sim)
```

## 기반 기술 / Technology Stack

[Kubernetes](https://kubernetes.io/) · [Helm](https://helm.sh/) ·
[kagent (CNCF)](https://kagent.dev/) · [Argo CD](https://argo-cd.readthedocs.io/) ·
[OpenTelemetry](https://opentelemetry.io/) ·
[Microsoft Sentinel](https://learn.microsoft.com/azure/sentinel/) ·
[LangGraph](https://langchain-ai.github.io/langgraph/) ·
[Ollama](https://ollama.com/) · [ArduPilot](https://ardupilot.org/)

## 문의 / Contact

**s1ns3nz0** · GitHub [@s1ns3nz0](https://github.com/s1ns3nz0) — 버그·제안은 각
저장소의 Issues로.

---

<sub>🌐 EN: **pollack** is a UAV cyber range that runs an offensive AI ↔ defensive
AI closed loop over a KUS-FS-class MUAV mission system. The red agent
(`fried-pollack-ai`) executes kill chains and emits `UAV*_CL` telemetry via
`run.py --emit-soc`; the blue agent (`pollack-ai`) consumes the same schema and
detects/responds. This repo (`pollack-infra`) is the Azure IaC that stands the
range up. Detection content ships from `dah-sentinel-content`.</sub>
