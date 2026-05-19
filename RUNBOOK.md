# Runbook: Tabular ML Pipeline

The operator drives the pipeline by hand, one Hermes session per agent. No autonomous supervisor.

## Prerequisites

- Hermes installed and authenticated (`hermes doctor` passes).
- A model + provider configured on the default profile (the four agent profiles inherit from it).
- This repo cloned; you're running commands from its root.
- Python venv activated with the deps in `requirements.txt` (pandas, pyarrow, scikit-learn, xgboost, openpyxl).

```bash
uv venv --python 3.11
source .venv/bin/activate
uv pip install -r requirements.txt
```

On macOS, xgboost also needs `libomp`:

```bash
brew install libomp
```

## One-time setup

Create the four agent profiles and copy in their skills:

```bash
bash scripts/setup_profiles.sh
```

This runs `hermes profile create` for each role (preprocessor, architect, trainer, reporter), copies each `skills/<role>/SKILL.md` into the matching `~/.hermes/profiles/<role>/SOUL.md`, and inherits `config.yaml` + `.env` from the default profile so each one has a model.

Verify:

```bash
hermes profile list                 # should show all four with a model
hermes -p preprocessor doctor       # should pass
```

## Per-session: four commands, in order

**Important:** activate the venv in the same shell from which you run `hermes`. The agents' `terminal` toolset inherits the parent shell's environment; without the venv active, `python scripts/...` won't find pandas/xgboost.

```bash
source .venv/bin/activate
```

Drop the client spreadsheet into `data/raw/`. Then run the four commands.

### 1. Preprocess

```bash
hermes -p preprocessor chat -t terminal,file -q "Process data/raw/<filename> with target=<col>" --yolo
```

The agent runs `scripts/prepare.py`, profiles the data, and writes `data/clean/clean.parquet` + `data/clean/profile.json`.

**Check before continuing:**
- `data/clean/clean.parquet` exists.
- `data/clean/profile.json` parses; `target` and `target_type` fields are right.
- The agent's stdout summary matches the data you uploaded.

### 2. Architect

```bash
hermes -p architect chat -t file -q "Read data/clean/profile.json and queue 2-3 configs" --yolo
```

The agent applies the size heuristic and writes 2–3 JSON configs into `runs/queue/`.

**Check before continuing:**
- `runs/queue/*.json` count is 2 or 3.
- Each config's `model` is one of `xgboost` or `logistic_regression` (the two supported by the minimal trainer).
- Each config's `params` look sane.

### 3. Train

```bash
hermes -p trainer chat -t terminal,file -q "Drain runs/queue/" --yolo
```

The agent runs `scripts/train.py` per config, appends one row to `runs/results.tsv` per run (success or failure), saves models under `models/`, and writes `runs/live/best.json` once the queue is empty.

**Check before continuing:**
- `runs/results.tsv` has one row per config.
- At least one row has `status=ok`.
- `runs/live/best.json` exists and references a model in `models/`.

### 4. Report

```bash
hermes -p reporter chat -t terminal,file -q "Render the final report" --yolo
```

The agent runs `scripts/render_report.py` and writes `reports/final.md` with an executive summary, headline metric, comparison table, and caveats.

**Open the report:**

```bash
open reports/final.md            # macOS
```

## Bonus: mid-pipeline interactive override

After the trainer's first drain, you can ask it to run an additional config in the same chat session — useful for a live demo when you want to show human-in-the-loop steering.

```bash
hermes -p trainer chat -t terminal,file --yolo
> drain runs/queue/
... [original 2-3 runs complete, ledger updated, best.json written] ...
> now also run a vanilla logistic regression with no tuning. append it to the same ledger.
... [trainer writes a new config, runs it, appends one row, recomputes best.json] ...
> exit
```

Then re-run the reporter to pick up the new state:

```bash
hermes -p reporter chat -t terminal,file -q "Render the final report" --yolo
```

The append-only ledger preserves the original runs alongside the new one; the report shows everything.

## Restart from scratch

```bash
rm -rf data/clean runs models reports
```

Then run the four commands again from step 1. `data/raw/` is untouched.

## Troubleshooting

| Symptom | First check |
|---|---|
| `hermes profile list` missing a profile | `bash scripts/setup_profiles.sh` again — it's idempotent |
| Preprocessor escalates "target column is ambiguous" | Pass `target=<col>` in the prompt |
| Architect escalates "queue not empty" | `rm runs/queue/*.json` and retry |
| Trainer all-failed | Check `runs/results.tsv` `secondary_metrics_json` for stderr tails. Most common cause: venv not active in the shell that ran hermes |
| Reporter says `best.json` missing | Trainer didn't produce a winner; revisit step 3 |
| Agent runs the script but errors with `ModuleNotFoundError` | Venv not active. Activate it and re-run the agent |

## What happens if you re-run a step

- **Preprocessor** overwrites `data/clean/`. Safe.
- **Architect** aborts if `runs/queue/` is not empty. Clear it first.
- **Trainer** appends to `runs/results.tsv` (append-only) and processes whatever is in `runs/queue/`. Clear the queue after a drain to avoid duplicate rows.
- **Reporter** overwrites `reports/final.md`. Safe.

## What's *not* in this runbook (yet)

- Cross-session memory: each Hermes profile has its own memory; nothing flows between sessions today.
- Telegram/Slack/IDE entry points. CLI only.
- Multi-GPU / distributed training. Single node, single device.
