# 🛰️ pollak-infra

![Azure](https://img.shields.io/badge/Azure-IaC-0078D4?logo=microsoftazure&logoColor=white)
![Bicep](https://img.shields.io/badge/Bicep-subscription--scope-00BCF2?logo=azuredevops&logoColor=white)
![AKS](https://img.shields.io/badge/AKS-Kubernetes-326CE5?logo=kubernetes&logoColor=white)
![Sentinel](https://img.shields.io/badge/Microsoft%20Sentinel-SIEM%2FSOAR-0078D4?logo=microsoft&logoColor=white)
![Region](https://img.shields.io/badge/region-Korea%20Central%2FSouth-0078D4)
![Loop](https://img.shields.io/badge/OCO%E2%86%94DCO-closed%20loop-e11d48)

**pollak** UAV 사이버 레인지를 위한 Azure 인프라(IaC). KUS-FS급 MUAV 임무
시스템을 대상으로 공격 ↔ 방어를 하나의 폐루프로 돌리는 시뮬레이션 환경이다.
이 저장소는 레인지 세 평면의 모든 클라우드 자원과 **평면 사이의 이음새(seam)** 를
소유한다. 평면 경계는 그 자체로 보안 산출물이라 각 애플리케이션 저장소에
흩뿌리지 않고 한 단위로 버전 관리·리뷰한다.

## 🎯 레인지 개요

레인지는 UAV 임무 시스템 전체(비행제어·데이터링크·GCS·ISR·무장·C4I — 13개
컨테이너, 19종 `UAV*_CL` 로그 테이블)를 모사하고, 그 위에서 실제 공격 ↔ 방어
루프를 돌린다. 작업은 세 개의 격리 평면으로 나뉘며, 각 평면은 독립된 AKS
클러스터 / VNet / 리소스 그룹이다.

| 평면 | 클러스터 | 역할 | 교리 |
|---|---|---|---|
| 🔴 **red** | `dah-red-aks` | 공격 측 — 자율 레드팀 에이전트가 실제 공격 흐름 실행 | OCO |
| 🟡 **sim** | `dah-sim-aks` | 표적 레인지 — UAV SITL·GCS·데이터링크·센서 | — |
| 🔵 **soc** | `dah-soc-aks` | 방어 측 — 탐지·상관분석·대응·대시보드 | DCO |

red가 sim을 공격하고, sim은 공유 SIEM으로 텔레메트리를 흘리며, soc는 그
텔레메트리로 탐지·대응한다. 두 에이전트가 하나의 폐루프를 이룬다 — 공격자의
행동이 곧 방어자의 증거가 되며, **red↔soc 직접 네트워크 경로는 없다**.

위협 모델은 **실제 신뢰경계**다. red는 살아있는 공격 도구를 돌리므로, 침해가
sim/soc의 제어평면·비밀·노드로 번져선 안 된다. 네임스페이스 분리는 약한
멀티테넌시이며 여기서는 신뢰경계가 *아니다* — 그래서 평면 간에는 클러스터
수준으로 격리한다.

## 🗂️ 저장소 생태계

레인지는 여러 저장소로 구성된다. 이 저장소는 클라우드 인프라와 평면 이음새를
담고, 애플리케이션 로직은 나머지 저장소에 있다.

| 저장소 | 계층 | 담는 것 |
|---|---|---|
| [**pollak-infra**](https://github.com/s1ns3nz0/pollack-infra) | infra | 이 저장소 — 세 평면 전체의 Azure IaC + 평면 사이 이음새 |
| [uav-sim-env](https://github.com/s1ns3nz0/uav-sim-env) | sim | KUS-FS급 MUAV SITL 레인지 (ArduPilot·13 컨테이너·19 `UAV*_CL` 테이블) |
| [fried-pollack-ai](https://github.com/s1ns3nz0/fried-pollack-ai) | red | OCO 레드팀 에이전트 — 공격 도구 + K8s 오버레이 |
| [pollack-ai](https://github.com/s1ns3nz0/pollack-ai) | soc | DCO-IDM 방어 AI SOC — 트리아지·상관분석·대응 |
| [dah-sentinel-content](https://github.com/s1ns3nz0/dah-sentinel-content) | soc | Sentinel **Detection-as-Code** — 공유 SIEM을 탐지로 바꾸는 분석 룰 |

**dah-sentinel-content** 는 이 저장소가 프로비저닝하는 `dah-data-law` Sentinel
워크스페이스의 탐지 콘텐츠 계층이다. 분석 룰 167개(단일 시그널 `S*` 탐지
131개 + 다단계 `C*` 캠페인 탐지 34개)에 헌팅 쿼리·파서·자동화 룰·플레이북·
워치리스트·워크북을 더해 GitHub Actions로 워크스페이스에 배포한다. 여기 인프라가
워크스페이스와 append-only 수집 경로를 만들고, 그 저장소가 UAV 공격에 발화하는
KQL로 그 안을 채운다.

## 🧩 이 저장소가 존재하는 이유

어느 한 평면에도 속하지 않아 애플리케이션 저장소에 둘 자리가 없는 자원들이
있다. 그것들이 여기 산다.

- red↔sim VNet 피어링 + Azure Firewall 이그레스 허용목록 (공격 경로)
- 공유 Azure Sentinel / Log Analytics 워크스페이스 `dah-data-law` — sim 탭은
  append-only로 쓰고, soc는 읽는다 (탐지 경로, sim↔soc 직접 피어링 **없음**)
- 프라이빗 DNS 존 (`*.pollak.store`, VNet 범위 split-horizon)
- 평면 경계를 강제하는 역할 할당 / RBAC

## 📁 구조

```
bicep/
  main.bicep          red 평면 (subscription 범위)
  sim.bicep           sim 평면 (subscription 범위)
  shared.bicep        평면 이음새 — 공유 SIEM 워크스페이스 (subscription 범위)
  modules/            평면별 · 이음새 모듈
  params/             lab*.bicepparam (작성자 환경) · judge*.bicepparam (리뷰어 템플릿)
scripts/
  deploy-red-with-sim.sh   멱등 sim(존재 시 건너뜀)+red 프로비저닝
```

애플리케이션 계층의 Kubernetes 매니페스트(kustomize 오버레이)는 각
애플리케이션 저장소에 남고, 여기에는 클라우드 인프라만 산다. GitOps 이미지
태그 갱신은 앱 저장소에서 일어나며, Sentinel 탐지 콘텐츠는
`dah-sentinel-content`에서 배포된다.

## 🚀 배포

이음새를 먼저 한 번 배포한다 (평면 배포 전 또는 동시에).

```bash
az deployment sub create --location koreacentral \
  --template-file bicep/shared.bicep --parameters bicep/params/lab-shared.bicepparam
```

평면을 미리보기하고 프로비저닝한다.

```bash
az deployment sub what-if --location koreacentral \
  --template-file bicep/main.bicep --parameters bicep/params/lab.bicepparam

scripts/deploy-red-with-sim.sh
```

**자기 구독에 배포하는 리뷰어 (Path B):** `bicep/params/judge.bicepparam`를
복사해 `REPLACE_*` 토큰을 채우고, `RED_PARAM_FILE` / `SIM_PARAM_FILE`로
스크립트를 그 파일에 물린다. 전체 런북은 red 앱 저장소의
`deploy/JUDGE-DEPLOY.md` 참고.

레인지가 올라오면 탐지 콘텐츠는
[dah-sentinel-content](https://github.com/s1ns3nz0/dah-sentinel-content)의
GitHub Actions 파이프라인으로 `dah-data-law` 워크스페이스에 배포된다.

---

<sub>🌐 English summary: Azure infrastructure-as-code for the **pollak** UAV
cyber range — a closed-loop OCO↔DCO simulation over a KUS-FS-class MUAV mission
system. Owns all cloud resources for the red/sim/soc planes and the cross-plane
seams (attack path, shared Sentinel workspace, private DNS, RBAC). Detection
content ships from
[dah-sentinel-content](https://github.com/s1ns3nz0/dah-sentinel-content).</sub>
