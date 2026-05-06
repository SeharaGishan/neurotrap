<div align="center">

<img src="assets/images/logo.png" alt="NeuroTrap Logo" width="180"/>

# NeuroTrap
### AI-Powered Smart Honeypot Detection System
*Security That Evolves*

[![License: CC BY-NC-ND 4.0](https://img.shields.io/badge/License-CC%20BY--NC--ND%204.0-lightgrey.svg)](https://creativecommons.org/licenses/by-nc-nd/4.0/)
![Python](https://img.shields.io/badge/Python-3.12.3-blue?logo=python)
![XGBoost](https://img.shields.io/badge/XGBoost-2.0.3-orange)
![PyTorch](https://img.shields.io/badge/PyTorch-2.12.0_nightly-red?logo=pytorch)
![CUDA](https://img.shields.io/badge/CUDA-12.8-green?logo=nvidia)
![AWS](https://img.shields.io/badge/AWS-ap--southeast--1-yellow?logo=amazonaws)
![Status](https://img.shields.io/badge/Status-Active_Research-brightgreen)

**BSc (Hons) Computer Security — PUSL3190 Final Year Project**
**University of Plymouth | NSBM Green University, Sri Lanka**

*Bedde K Samarasinghe — Plymouth Index: 10953243*

---

| 0.9993 | 1.0000 | 283.4 | 33.1 | 65.4 | +2204% |
|:---:|:---:|:---:|:---:|:---:|:---:|
| **XGBoost Macro F1** | **XGBoost AUC** | **DQN v3 Adv Reward** | **Avg Steps Engaged** | **Intel Captured/Session** | **v1 → v3 Gain** |
| Test Set — 2.8M samples | Perfect class separation | vs 12.3 in v1 baseline | vs 3.0 in v1 (+1,003%) | vs 9.0 in v1 | Advanced adversary reward |

</div>

---

## Table of Contents

- [Overview](#overview)
- [Research Gap & Novelty](#research-gap--novelty)
- [System Architecture](#system-architecture)
- [AI Pipeline](#ai-pipeline)
- [Honeypot Services](#honeypot-services)
- [Data Pipeline](#data-pipeline)
- [AWS Infrastructure](#aws-infrastructure)
- [Mobile Dashboard](#mobile-dashboard)
- [Tech Stack](#tech-stack)
- [Project Structure](#project-structure)
- [Results](#results)
- [Citation](#citation)
- [License](#license)

---

## Overview

**NeuroTrap** is a research-grade, AI-powered adaptive honeypot system that combines real-time attacker classification with dynamic deception. Unlike traditional static honeypots that treat all attackers identically, NeuroTrap intelligently profiles each attacker in real time and adapts its behaviour to maximise threat intelligence capture while keeping adversaries engaged longer.

The system integrates a **two-stage closed-loop AI architecture**: an XGBoost attacker profiler that classifies sessions into three threat categories (automated bot, script kiddie, advanced persistent threat), feeding directly into a Deep Q-Network (DQN) adaptive deception agent that selects the optimal deception strategy for each attacker type — in under 200 microseconds.

**Core Objectives:**
1. Monitor attacker behaviour across multiple honeypot services (SSH, web, malware)
2. Classify attackers in real time using XGBoost (bot / script kiddie / APT)
3. Adapt honeypot responses dynamically using a DQN reinforcement learning agent
4. Visualise attacker data and push real-time alerts via a Flutter mobile dashboard

---

## Research Gap & Novelty

Existing honeypot solutions fall into two categories: **static deception tools** (Honeyd, Kippo) and **isolated proof-of-concept RL frameworks** (QRASSH). Neither provides a production-ready platform integrating real-time profiling with adaptive deception.

NeuroTrap addresses this by delivering **six original research contributions**:

| # | Contribution |
|---|---|
| 1 | First operational integration of a real-time XGBoost profiler with a DQN deception agent in a single closed-loop system |
| 2 | State-conditioned reward function using live XGBoost probability outputs `[P(bot), P(sk), P(adv)]` as DQN reward multipliers |
| 3 | Curiosity-driven per-action intrinsic exploration bonus applied to honeypot deception policy training |
| 4 | Action synergy chain: `delay_response → change_filesystem → inject_fake_data` cascading reward structure |
| 5 | Largest multi-source honeypot training dataset: 32.9M balanced samples from 8 heterogeneous sources |
| 6 | Three-version iterative DQN methodology with documented policy collapse diagnosis and theoretical analysis |

> **Benchmark exceeded:** NeuroTrap's XGBoost profiler achieves 99.96% accuracy — surpassing the published state-of-the-art benchmark of 90% detection rate (Kumrashan Indranil Iyer, 2021) by **9.93 percentage points**.

---

## System Architecture

```
Internet (Attackers)
        │
        ▼
┌─────────────────────────────────────────┐
│         AWS VPC — ap-southeast-1        │
│  ┌──────────────────────────────────┐   │
│  │        Public Subnet 10.0.1.0/24 │   │
│  │  ┌──────────┐  ┌─────────────┐  │   │
│  │  │Web Decoy │  │ File Decoy  │  │   │
│  │  │(Apache)  │  │ (SMB Share) │  │   │
│  │  └──────────┘  └─────────────┘  │   │
│  │  ┌───────────────────────────┐  │   │
│  │  │   NeuroTrap Honeypot      │  │   │
│  │  │  Cowrie SSH (:22)         │  │   │
│  │  │  Dionaea SMB/MySQL (:445) │  │   │
│  │  │  Web Honeypot (:80)       │  │   │
│  │  │  Zeek Network Monitor     │  │   │
│  │  └───────────┬───────────────┘  │   │
│  └──────────────┼───────────────── ┘   │
│                 │ Filebeat log stream   │
│  ┌──────────────▼───────────────────┐  │
│  │       Private Subnet 10.0.2.0/24 │  │
│  │  ┌──────────┐  ┌──────────────┐  │  │
│  │  │  ELK     │  │  AI Engine   │  │  │
│  │  │  Stack   │◄─│  XGBoost +   │  │  │
│  │  │          │  │  DQN Agent   │  │  │
│  │  └──────────┘  └──────┬───────┘  │  │
│  │  ┌────────────────────▼───────┐  │  │
│  │  │  Grafana Dashboard (:3000) │  │  │
│  │  └────────────────────────────┘  │  │
│  └──────────────────────────────────┘  │
└─────────────────────────────────────────┘
        │ FCM Push Alerts
        ▼
  Flutter Mobile App
```

---

## AI Pipeline

### Stage 1 — XGBoost Attacker Profiler

The XGBoost classifier processes 45 behavioural features extracted from raw honeypot logs and outputs a real-time 3-class probability vector in **50–200 microseconds** per session.

```
Raw Honeypot Logs
      │
      ▼
Feature Extractor (45 features)
      │  session_duration, credential_count, client_fingerprint,
      │  port_scan_pattern, payload_entropy, command_sequence...
      ▼
StandardScaler (fitted on training data)
      │
      ▼
XGBoost Classifier (xgboost_attacker_profiler.ubj — 3.9MB)
      │
      ▼
[P(bot), P(script_kiddie), P(advanced_adversary)]
      │
      ▼
DQN Agent State Input
```

**Training Results:**

| Metric | Score |
|--------|-------|
| Macro F1 | **0.9993** |
| Accuracy | **0.9996** |
| Macro AUC | **1.0000** |
| Best Round | 313 / 500 (early stopping) |
| Training Time | 2.8 minutes (RTX 5070 Ti) |
| Training Samples | 32,971,269 (SMOTE-balanced) |

### Stage 2 — DQN Adaptive Deception Agent

The DQN agent receives the XGBoost probability vector as its state and selects the optimal deception action for the current attacker class.

**Action Space (7 actions):**

```python
actions = [
    "delay_response",       # Introduce network delays — effective vs APT
    "change_filesystem",    # Mutate fake file system responses
    "inject_fake_data",     # Plant convincing fake credentials/files
    "open_fake_service",    # Spin up a decoy service — effective vs script kiddie
    "close_service",        # Remove a service to test attacker reaction
    "escalate_logging",     # Increase capture verbosity
    "do_nothing"            # Conserve resources for confirmed bots
]
```

**State-Conditioned Reward Function (Novel Contribution):**

```python
# Reward multipliers driven by live XGBoost output
if action == "delay_response":
    reward += 3.0 if P_adv > 0.5 else -0.8 if P_bot > 0.7 else 0

if action == "do_nothing":
    reward += 1.5 if P_bot > 0.7 else -0.5 if P_sk > 0.6 else 0

if action == "open_fake_service":
    reward += 2.5 if P_sk > 0.6 else 0

if action == "inject_fake_data":
    reward -= 1.5 if P_bot > 0.7 else 0  # Penalise resource waste on bots
```

**DQN Version Progression:**

| Version | Adv Reward | Avg Steps | Intel/Session | Key Fix |
|---------|-----------|-----------|---------------|---------|
| v1 (baseline) | 12.3 | 3.0 | 9.0 | — |
| v2 | 47.8 | 11.2 | 28.4 | Class-conditional sampling |
| v3 (production) | **283.4** | **33.1** | **65.4** | State-conditioned rewards + curiosity exploration |
| **Improvement** | **+2,204%** | **+1,003%** | **+627%** | |

---

## Honeypot Services

All services deployed inside Docker containers on an isolated bridge network:

| Service | Tool | Port | What It Captures |
|---------|------|------|-----------------|
| SSH Honeypot | Cowrie | 22 | Brute force attempts, credentials, session commands, client fingerprints |
| SMB/MySQL/MSSQL/FTP | Dionaea | 445, 3306, 1433, 21 | Malware downloads, exploit attempts, connection metadata |
| Web Honeypot | Custom Flask | 80 | Path scanning, HTTP attack patterns, bot fingerprints |
| Network Monitor | Zeek | — | Packet-level flow analysis, protocol metadata, anomaly detection |

**Live Deployment Period:** 22 February 2026 – 26 March 2026 (33 days) on a public-facing AWS EC2 instance.

---

## Data Pipeline

Six sequential preprocessing scripts transform raw logs into ML-ready training arrays:

```
01_parse_cowrie.py      →  333 SSH sessions from 33 daily JSON log files
02_parse_dionaea.py     →  6,851 malware connections from 1.88GB log
03_parse_web_honeypot.py→  1,986 HTTP requests from Flask honeypot
04_process_public_datasets.py → 25,630,718 records (Kaggle + Mendeley + Zenodo)
05_parse_beth_unsw.py   →  46,155 verified APT ground-truth records
06_merge_and_split.py   →  32,971,269 SMOTE-balanced training samples
```

**Final Dataset:**

| Split | Samples | Distribution |
|-------|---------|--------------|
| Train | 32,971,269 | Perfectly balanced (SMOTE) — 10,990,423 per class |
| Validation | 2,798,402 | Natural distribution |
| Test | 2,798,402 | Natural distribution (held out) |
| **Total** | **38,567,073** | |

**Public Datasets Used:**
- CyberLab Honeypot Dataset (Zenodo) — 9-month Cowrie SSH capture
- Cybersecurity Honeypot Attacks (Kaggle / Dionaea)
- Honeypot Data UMM (Mendeley Data)
- BETH Dataset — verified advanced adversary forensics
- UNSW-NB15 — professional red team operations

---

## AWS Infrastructure

Deployed on AWS ap-southeast-1 (Singapore) with a VPC dual-subnet architecture:

**Public Subnet (10.0.1.0/24) — Attack Surface:**

| Instance | Type | Role |
|----------|------|------|
| NeuroTrap Honeypot | t3.medium | Cowrie + Dionaea + Web Honeypot + Zeek |
| Web Decoy | t3.micro | Apache fake company site |
| File Decoy | t3.micro | SMB share with fake documents |

**Private Subnet (10.0.2.0/24) — Protected Backend:**

| Instance | Type | Role |
|----------|------|------|
| AI Engine | t3.large (2vCPU/8GB) | FastAPI inference, XGBoost + DQN, deception controller |
| ELK Stack | t3.medium | Elasticsearch, Logstash, Kibana — log normalisation |
| Grafana Dashboard | t3.small | Live attacker visualisation |

---

## Mobile Dashboard

A cross-platform Flutter mobile application delivers real-time threat intelligence directly to the security team:

**Alert Classification:**
- 🟢 **Bot detected** — silent notification
- 🟡 **Script kiddie** — alarm sound alert
- 🔴 **Advanced adversary (APT)** — CRITICAL full-screen alert with push sound

**Features:**
- Live session dashboard with XGBoost confidence scores
- DQN action history and deception decision log
- Geographic source map and intel captured counter
- Alert timeline with attacker classification breakdown
- Firebase Cloud Messaging (FCM) real-time push notifications

---

## Tech Stack

**AI & Machine Learning:**
```
XGBoost 2.0.3          — Attacker profiler (GPU-accelerated, CUDA 12.8)
PyTorch 2.12.0 nightly — DQN training (Blackwell sm_120 support)
scikit-learn 1.5.0     — Preprocessing, SMOTE, StandardScaler
imbalanced-learn 0.12.3— SMOTE class balancing
MLflow 2.13.0          — Experiment tracking
```

**Honeypot & Network:**
```
Cowrie                 — SSH/Telnet honeypot
Dionaea                — Malware capture honeypot
Custom Flask           — Web honeypot
Zeek                   — Network-level traffic analysis
```

**Infrastructure & Deployment:**
```
AWS EC2                — ap-southeast-1 (Singapore)
Docker + Compose       — Container orchestration
FastAPI                — Real-time inference API
ELK Stack              — Log ingestion and normalisation
Grafana                — Visualisation dashboard
Filebeat               — Log shipping
Firebase FCM           — Mobile push notifications
```

**Mobile:**
```
Flutter                — Cross-platform mobile dashboard
Firebase Realtime DB   — Live data sync
```

**Development Environment:**
```
Ubuntu 24.04 LTS (WSL2)
Intel Core Ultra 9 285K — 24 cores
NVIDIA RTX 5070 Ti 16GB VRAM — Blackwell sm_120
32GB DDR5 RAM (24GB WSL2 allocated)
Python 3.12.3 in isolated venv
```

---

## Project Structure

```
neurotrap/
├── preprocessing/
│   ├── 01_parse_cowrie.py
│   ├── 02_parse_dionaea.py
│   ├── 03_parse_web_honeypot.py
│   ├── 04_process_public_datasets.py
│   ├── 05_parse_beth_unsw.py
│   └── 06_merge_and_split.py
├── models/
│   ├── xgboost_attacker_profiler.ubj   # Primary inference model (3.9MB)
│   ├── xgboost_attacker_profiler.json  # Human-readable model
│   ├── xgboost_metadata.json
│   ├── dqn_v3_best.pth                 # Production DQN (episode 55,000)
│   ├── dqn_v3_final.pth
│   └── dqn_v3_metadata.json
├── training_data/
│   ├── scaler.joblib                   # StandardScaler (apply before inference)
│   ├── feature_columns.joblib          # 45 feature names in correct order
│   └── class_weights.joblib
├── results/
│   ├── classification_report.txt
│   ├── confusion_matrix.png
│   ├── feature_importance.png
│   ├── roc_curves.png
│   ├── training_curves.png
│   ├── dqn_v3_training.png
│   └── dqn_v3_policy.txt
├── inference/
│   └── api.py                          # FastAPI real-time inference server
├── honeypot/
│   ├── docker-compose.yml
│   ├── cowrie/
│   ├── dionaea/
│   └── web-honeypot/
├── aws/
│   └── neurotrap-ids.sh                # AWS infrastructure setup script
├── dashboard/
│   └── flutter_app/                    # Flutter mobile application
├── docs/
│   └── assets/
└── README.md
```

---

## Results

### XGBoost Attacker Profiler

| Class | Precision | Recall | F1 |
|-------|-----------|--------|----|
| Automated Bot | 0.9998 | 0.9999 | 0.9999 |
| Script Kiddie | 0.9991 | 0.9989 | 0.9990 |
| Advanced Adversary | 0.9992 | 0.9994 | 0.9993 |
| **Macro Average** | **0.9994** | **0.9994** | **0.9993** |

- Inference latency: **50–200 microseconds** per session
- Model size: **3.9MB** (binary .ubj format)
- Training time: **2.8 minutes** on NVIDIA RTX 5070 Ti

### DQN Adaptive Deception Agent (v3)

| Attacker Class | Reward | Avg Steps | Intel Captured |
|---------------|--------|-----------|----------------|
| Automated Bot | 18.2 | 8.4 | 12.1 |
| Script Kiddie | 94.7 | 19.6 | 38.3 |
| Advanced Adversary | **283.4** | **33.1** | **65.4** |

---

## Citation

If you use, reference, or build upon NeuroTrap in academic or research work, please cite:

**APA:**
```
Samarasinghe, B. K. (2026). NeuroTrap: AI-Powered Smart Honeypot Detection System
for Adaptive Intrusion Detection and Attacker Profiling [Final Year Project].
University of Plymouth. https://github.com/[your-username]/neurotrap
```

**BibTeX:**
```bibtex
@misc{samarasinghe2026neurotrap,
  author    = {Samarasinghe, Bedde K.},
  title     = {NeuroTrap: AI-Powered Smart Honeypot Detection System
               for Adaptive Intrusion Detection and Attacker Profiling},
  year      = {2026},
  publisher = {GitHub},
  url       = {https://github.com/[your-username]/neurotrap},
  note      = {BSc (Hons) Computer Security, University of Plymouth,
               PUSL3190 Final Year Project}
}
```

---

## License

Copyright © 2026 Bedde K Samarasinghe. All rights reserved.

This project is licensed under the **Creative Commons Attribution-NonCommercial-NoDerivatives 4.0 International License**.

[![License: CC BY-NC-ND 4.0](https://img.shields.io/badge/License-CC%20BY--NC--ND%204.0-lightgrey.svg)](https://creativecommons.org/licenses/by-nc-nd/4.0/)

You may **share** this work with attribution for non-commercial purposes. You may **not** use it commercially, distribute modified versions, or incorporate it into other projects without explicit written permission from the author.

See the [LICENSE](LICENSE) file for full terms.

---

> ⚠️ **Disclaimer:** NeuroTrap is a research prototype developed for academic purposes under controlled conditions. It is not intended for deployment in production environments without appropriate security review and professional authorisation. The author accepts no responsibility for misuse of this software.

---

<div align="center">
<i>NeuroTrap — Security That Evolves</i><br/>
<i>BSc (Hons) Computer Security — University of Plymouth — 2026</i>
</div>
