# Agentic Learning Series — Tabular ML Pipeline Demo

A multi-agent ML pipeline that turns a client's spreadsheet into a trained model and a one-page decision-support report — all inside hardened NemoClaw sandboxes.

> **One-line story:** "Drop a CSV in, get a model and a report out — four agents, two sandboxes, zero trust."

## What It Does


| Stage         | Agent          | What It Produces                            |
| ------------- | -------------- | ------------------------------------------- |
| 1. Preprocess | `preprocessor` | Cleaned Parquet + data profile JSON         |
| 2. Architect  | `architect`    | 2-3 model configurations in the queue       |
| 3. Train      | `trainer`      | Trained models + append-only results ledger |
| 4. Report     | `reporter`     | Client-facing markdown report               |


## Architecture

Two NemoClaw sandboxes with different security levels:

- `**data-pipeline`** — NVIDIA inference API + local gateway only
- `**reporter**` — Zero network (completely blocked)

Both use Landlock filesystem locks, seccomp syscall filtering, and run as an unprivileged `sandbox` user.

## Prerequisites

- **NemoClaw installed** — `nemoclaw` and `openshell` on PATH
- **Hermes installed** — `hermes` on PATH with a configured model and provider
- **Docker** — running (for OpenShell sandboxes)
- **NVIDIA inference API** — configured in `~/.nemoclaw/credentials.json`

## Installation

Run from the repository root.

### 1. Create the sandboxes

Each uses an interactive wizard. When prompted, select:

- Inference provider: `Local Ollama`
- Model: `qwen3.6:35b` (or your preferred model)

```bash
nemoclaw onboard --agent hermes --name data-pipeline
nemoclaw onboard --agent hermes --name reporter
```

### 2. Apply network policies

```bash
# data-pipeline: allow only NVIDIA inference + local gateway
openshell policy set --policy policy_new/demo-pipeline-restricted.yaml data-pipeline --wait

# reporter: allow to install Python dependencies
openshell policy set --policy policy_new/reporter-setup.yaml reporter --wait
```

### 3. Upload files to `data-pipeline` sandbox

```bash
# Data, scripts, agent config, requirements
for f in data/raw/telco-churn.csv scripts/prepare.py scripts/train.py \
         scripts/render_report.py AGENTS.md requirements.txt; do
  openshell sandbox upload data-pipeline "$f" "/sandbox/$f"
done

# Agent skills (preprocessor, architect, trainer)
for role in preprocessor architect trainer; do
  openshell sandbox upload data-pipeline \
    "skills/$role/SKILL.md" "/sandbox/skills/$role/SKILL.md"
done
```

### 4. Upload files to `reporter` sandbox

```bash
for f in scripts/render_report.py AGENTS.md requirements.txt; do
  openshell sandbox upload reporter "$f" "/sandbox/$f"
done
openshell sandbox upload reporter \
  "skills/reporter/SKILL.md" "/sandbox/skills/reporter/SKILL.md"
```

### 5. Install Python dependencies inside sandboxes

```bash
openshell sandbox exec -n data-pipeline \
  bash -c 'python3 -m venv /sandbox/.venv && /sandbox/.venv/bin/pip install -r /sandbox/requirements.txt'

openshell sandbox exec -n reporter \
  bash -c 'python3 -m venv /sandbox/.venv && /sandbox/.venv/bin/pip install -r /sandbox/requirements.txt'
```

### 6. Apply `reporter` network policies

```bash
# reporter: zero network (completely blocked)
openshell policy set --policy policy_new/reporter-restricted.yaml reporter --wait
```

### 7. Create local Python venv

For running the pipeline locally (outside sandboxes):

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

### 8. Set up Hermes profiles

Creates profiles for each agent role (preprocessor, architect, trainer, reporter), inheriting your default model configuration:

```bash
bash scripts/setup_profiles.sh
```

### 8. Verify

```bash
nemoclaw list
openshell policy get data-pipeline
openshell policy get reporter
```

## Running the Pipeline

Sandboxes:
  data-pipeline    → NVIDIA inference only (blocked: everything else)
  reporter         → ZERO network (completely blocked)

Files uploaded:
  data-pipeline: telco-churn.csv, prepare.py, train.py,
                 skills/preprocessor/SKILL.md, skills/architect/SKILL.md,
                 skills/trainer/SKILL.md, AGENTS.md
  reporter:      render_report.py, skills/reporter/SKILL.md, AGENTS.md

### 1. Full run for `data-pipeline` sandbox (preprocessor -> architect -> trainer)

```bash
bash scripts/run_pipeline.sh data/raw/telco-churn.csv Churn
```

### OR: Step by step (recommended for demos)

```bash
# 1. Preprocess — clean data and generate profile
openshell sandbox exec -n data-pipeline bash -c "hermes -p preprocessor \
chat -t terminal.file -q "Process $INPUT with target=$TARGET" --yolo"

# 2. Architect — queue 2-3 model configs based on profile
openshell sandbox exec -n data-pipeline bash -c "hermes -p architect chat -t file \
-q "Read data/clean/profile.json and queue 2-3 configs" --yolo"

# 3. Train — execute every queued config
openshell sandbox exec -n data-pipeline bash -c "hermes -p trainer chat -t terminal,file \
-q "Train runs/queue/" --yolo"

# Download the files for report generation:
openshell sandbox download data-pipeline /sandbox/runs/live/best.json runs/live/best.json
openshell sandbox download data-pipeline /sandbox/runs/results.tsv runs/results.tsv
openshell sandbox download data-pipeline /sandbox/models/ models
openshell sandbox download data-pipeline /sandbox/data/clean/profile.json data/clean/profile.json
```

### 2. Upload results to `reporter` and generate the report:

```bash
openshell sandbox upload reporter runs/ /sandbox --no-git-ignore
openshell sandbox upload reporter data/ /sandbox --no-git-ignore
openshell sandbox upload reporter models/ /sandbox --no-git-ignore

# Report — generate client-facing report
openshell sandbox exec -n reporter bash -c "hermes -p reporter chat -t terminal,file \
  -q "Render the final report" --yolo"

# Download report
openshell sandbox download reporter /sandbox/reports/final.md reports/final.md
```

### 3. Security demo

```bash
bash scripts/demo-security.sh
```

Demonstrates network egress blocking, Landlock filesystem enforcement, process isolation, and data separation.

## Expected Output

After a full run:

```
data/clean/clean.parquet       # Cleaned dataset (12,330 rows x 20 features)
data/clean/profile.json        # Data profile with target, dtypes, missingness
runs/results.tsv               # Append-only ledger (3 rows: LR, XGB, LGBM)
runs/live/best.json            # Winning run summary
models/<run_id>.pkl            # Trained model artifacts
reports/final.md               # Client-facing report with executive summary,
                               # model comparison, SHAP feature importance,
                               # and caveats
```

## Restart from scratch

```bash
rm -rf data/clean/ runs/ models/ reports/
```

Then re-run the pipeline stages. `data/raw/` is untouched.

## Troubleshooting


| Issue                                       | Fix                                                        |
| ------------------------------------------- | ---------------------------------------------------------- |
| Hermes profiles missing                     | Run `bash scripts/setup_profiles.sh` — it's idempotent     |
| Agent can't find pandas/xgboost             | Activate the venv: `source .venv/bin/activate`             |
| Preprocessor says "target column ambiguous" | Pass `target=<col>` in the prompt explicitly               |
| Architect says "queue not empty"            | `rm runs/queue/*.json` and retry                           |
| All training runs failed                    | Check `runs/results.tsv` secondary_metrics_json for stderr |
| Reporter says best.json missing             | Trainer didn't produce a winner; check step 3              |
| Sandbox policy not applied                  | `openshell policy get <name> --full`                       |
| `l7_decision=deny` in logs                  | Re-run `openshell policy set`                              |


