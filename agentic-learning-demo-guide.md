# Agentic Learning Series: Tabular ML Pipeline Demo

Your AI agent turns a client's spreadsheet into a trained ML model and a one-page decision-support report — all inside hardened NemoClaw sandboxes.

> **One-line story:** "Drop a CSV in, get a model and a report out — four agents, two sandboxes, zero trust."

---

## What You Get

| Capability | Description |
|---|---|
| **Multi-agent pipeline** | Four specialized agents (preprocessor, architect, trainer, reporter) hand off work via structured artifacts |
| **Dual-sandbox security** | `data-pipeline` sandbox (NVIDIA inference only) + `reporter` sandbox (zero network) — YAML-defined policies enforced by OpenShell |
| **Append-only ledger** | Every training run recorded immutably in `results.tsv` — full audit trail |
| **Client-facing report** | Auto-generated markdown report with SHAP feature importance, model comparison, and caveats |
| **Security demo** | Live demonstration of Landlock filesystem locks, network egress blocking, and user isolation |

### What makes it different

Other demos in this repo add a single capability (vision, speech, NASA photos) to an agent. This demo showcases **multi-agent orchestration with security-first sandboxing** — two isolated sandboxes, four distinct agent roles, and a fully auditable ML pipeline. It's designed for ALS booth demos where security and governance matter as much as the AI.

---

## Prerequisites

| Requirement | Details |
|---|---|
| NemoClaw installed | `nemoclaw onboard` completed |
| OpenShell CLI | `openshell` on PATH |
| Hermes CLI | `hermes` on PATH with a configured model + provider |
| Python 3.11+ venv | With `pandas`, `pyarrow`, `scikit-learn`, `xgboost`, `openpyxl` |
| Docker | Running (for OpenShell sandboxes) |
| NVIDIA inference API | Configured in `~/.nemoclaw/credentials.json` |

---

## Quick Start

```bash
cd agentic-learning-demo
bash install.sh
```

The script:
1. Checks prerequisites (`openshell`, `nemoclaw`, `hermes`)
2. Creates two sandboxes: `data-pipeline` (inference only) and `reporter` (zero network)
3. Applies YAML network policies to each sandbox
4. Uploads scripts, agent skills, and sample data into the sandboxes
5. Installs Python dependencies inside each sandbox
6. Sets up local Hermes profiles for the four agent roles
7. Verifies everything is ready

---

## Manual Setup

If you prefer to install step by step.

### Step 1: Create sandboxes and apply policies

```bash
nemoclaw onboard --name data-pipeline
nemoclaw onboard --name reporter
openshell policy set --policy policy/demo-pipeline-restricted.yaml data-pipeline --wait
openshell policy set --policy policy/reporter-restricted.yaml reporter --wait
```

### Step 2: Upload files to `data-pipeline` sandbox

```bash
for f in data/raw/telco-churn.csv scripts/prepare.py scripts/train.py scripts/render_report.py AGENTS.md requirements.txt; do
  openshell sandbox upload data-pipeline "$f" "/sandbox/$f"
done
```

Upload skills:

```bash
for role in preprocessor architect trainer; do
  openshell sandbox upload data-pipeline "skills/$role/SKILL.md" "/sandbox/skills/$role/SKILL.md"
done
```

### Step 3: Upload files to `reporter` sandbox

```bash
for f in scripts/render_report.py AGENTS.md requirements.txt; do
  openshell sandbox upload reporter "$f" "/sandbox/$f"
done
openshell sandbox upload reporter "skills/reporter/SKILL.md" "/sandbox/skills/reporter/SKILL.md"
```

### Step 4: Install Python deps inside sandboxes

```bash
openshell sandbox exec -n data-pipeline bash -c 'python3 -m venv /sandbox/.venv && /sandbox/.venv/bin/pip install -r /sandbox/requirements.txt'
openshell sandbox exec -n reporter bash -c 'python3 -m venv /sandbox/.venv && /sandbox/.venv/bin/pip install -r /sandbox/requirements.txt'
```

### Step 5: Set up local Hermes profiles

```bash
bash scripts/setup_profiles.sh
```

This creates `hermes profile` entries for `preprocessor`, `architect`, `trainer`, and `reporter`, each inheriting your default model configuration.

---

## Running the Pipeline

### Option A: Full automated run

```bash
source .venv/bin/activate
bash scripts/run_pipeline.sh data/raw/telco-churn.csv Churn
```

This runs all four stages sequentially in separate Hermes sessions.

### Option B: Step by step (recommended for demos)

```bash
source .venv/bin/activate

# 1. Preprocess — clean data and generate profile
hermes -p preprocessor chat -t terminal,file -q "Process data/raw/telco-churn.csv with target=Churn" --yolo

# 2. Architect — queue 2-3 model configs based on profile
hermes -p architect chat -t file -q "Read data/clean/profile.json and queue 2-3 configs" --yolo

# 3. Train — execute every queued config
hermes -p trainer chat -t terminal,file -q "Drain runs/queue/" --yolo

# 4. Report — generate client-facing report
hermes -p reporter chat -t terminal,file -q "Render the final report" --yolo
```

---

## Demo Prompts

### Hook — "From spreadsheet to model"

```text
Process data/raw/telco-churn.csv with target=Churn
```

The preprocessor agent reads the CSV, infers dtypes, profiles missingness, handles the target column, and outputs `clean.parquet` + `profile.json`.

### Pipeline walkthrough

```text
Read data/clean/profile.json and queue 2-3 configs
```

The architect reads the data profile and proposes 2-3 model configurations using a size heuristic (small/medium/large dataset strategies).

### Training run

```text
Drain runs/queue/
```

The trainer executes every config, records results in an append-only ledger, saves model artifacts, and identifies the winner.

### Final report

```text
Render the final report
```

The reporter reads the ledger, best model, and data profile to generate a client-facing markdown report with executive summary, SHAP feature importance, and caveats.

### Security demo

```bash
bash scripts/demo-security.sh
```

This script runs live checks against both sandboxes demonstrating:
- Network egress blocking (reporter can't reach the internet)
- Network allowlisting (data-pipeline only reaches NVIDIA inference)
- Landlock filesystem enforcement (can't write to `/etc` or `/usr`)
- Process isolation (sandbox user, not root)
- Data separation (reporter can't see raw data)

---

## Expected Output

After a full run, you get:

```
data/clean/clean.parquet       # Cleaned dataset (12,330 rows x 20 features)
data/clean/profile.json        # Data profile with target, dtypes, missingness
runs/results.tsv               # Append-only ledger (3 rows: LR, XGB, LGBM)
runs/live/best.json            # Winning run summary
models/<run_id>.pkl            # Trained model artifacts
reports/final.md               # Client-facing report with:
                               #   - Executive summary
                               #   - Model comparison table
                               #   - SHAP feature importance
                               #   - Caveats and limitations
```

---

## File Structure

```
agentic-learning-demo/
├── install.sh                        # Automated installer
├── agentic-learning-demo-guide.md         # This guide
├── AGENTS.md                        # Agent operating contract (hand-off rules, schemas)
├── requirements.txt                 # Python dependencies
├── policy/
│   ├── demo-pipeline-restricted.yaml  # data-pipeline sandbox: NVIDIA inference only
│   └── reporter-restricted.yaml       # reporter sandbox: zero network
├── skills/
│   ├── preprocessor/
│   │   └── SKILL.md                 # Preprocessor agent skill
│   ├── architect/
│   │   └── SKILL.md                 # Architect agent skill
│   ├── trainer/
│   │   └── SKILL.md                 # Trainer agent skill
│   └── reporter/
│       └── SKILL.md                 # Reporter agent skill
├── scripts/
│   ├── setup_profiles.sh           # Create Hermes profiles for each agent role
│   ├── setup-demo.sh               # Full sandbox setup (legacy, use install.sh)
│   ├── run_pipeline.sh             # Run all four stages sequentially
│   ├── demo-security.sh            # Live security demonstration script
│   ├── prepare.py                  # Data preprocessing script
│   ├── train.py                    # Model training script
│   └── render_report.py            # Report generation script
├── data/
│   └── raw/
│       └── telco-churn.csv         # Sample dataset (included for demos)
├── agentic-learning-setup.svg              # Architecture diagram (SVG)
└── agentic-learning-setup.excalidraw       # Architecture diagram (Excalidraw source)
```

---

## Troubleshooting

| Issue | Fix |
|---|---|
| Hermes profiles missing | Run `bash scripts/setup_profiles.sh` — it's idempotent |
| Agent can't find pandas/xgboost | Activate the venv: `source .venv/bin/activate` before running Hermes |
| Preprocessor says "target column ambiguous" | Pass `target=<col>` in the prompt explicitly |
| Architect says "queue not empty" | `rm runs/queue/*.json` and retry |
| All training runs failed | Check `runs/results.tsv` secondary_metrics_json for stderr tails |
| Reporter says best.json missing | Trainer didn't produce a winner; check step 3 |
| Sandbox policy not applied | Verify with `openshell policy get <sandbox-name> --full` |
| `l7_decision=deny` in OpenShell logs | Policy YAML not loaded correctly; re-run `openshell policy set` |
| Conference Wi-Fi fails during model pulls | The demo uses NVIDIA inference API; ensure credentials are configured |

---

## Restart from scratch

```bash
rm -rf data/clean/ runs/ models/ reports/
```

Then re-run the four pipeline stages. `data/raw/` is untouched.

---

## Security Architecture

The demo uses two sandboxes with different security levels:

```
┌────────────────────── data-pipeline ──────────────────────┐
│  Network:  NVIDIA inference API + local gateway only      │
│  Filesys:  /sandbox r/w, /etc and /usr read-only          │
│  User:     sandbox (unprivileged)                         │
│  Agents:   preprocessor, architect, trainer               │
│  Data:     Has access to raw CSV input                    │
└────────────────────────────────────────────────────────────┘

┌────────────────────── reporter ───────────────────────────┐
│  Network:  NONE (completely blocked)                      │
│  Filesys:  /sandbox r/w, /etc and /usr read-only          │
│  User:     sandbox (unprivileged)                         │
│  Agents:   reporter                                       │
│  Data:     Receives only results.tsv + best.json          │
└────────────────────────────────────────────────────────────┘
```

Policies are defined in YAML (`policy/*.yaml`) and applied live via `openshell policy set` — no sandbox restart required.
