# AGENTS.md

Operating contract for every agent in this repo. Read this first; the rules here win over anything in your individual persona file.

## What this repo is

A four-agent pipeline that turns a client's spreadsheet into a tabular ML model plus a one-page decision-support report.

Stack: NemoClaw sandbox (OpenShell isolation) + Hermes (single process, sub-agent delegation) + RAPIDS for data and training, with transparent CPU fallback.

## Diagrams

- **Setup guide (Excalidraw):** https://excalidraw.com/#json=Bp6Up7SZu4rN21cpMA5Yo,9etHITeVufwTQLsh_g7Yow
- **Setup guide (SVG):** `agentic-learning-setup.svg`
- **Setup guide (JSON):** `agentic-learning-setup.excalidraw`
- **Setup script:** `bash scripts/setup-demo.sh` (idempotent, full setup from scratch)

## The pipeline

```
user → supervisor → preprocessor → architect → trainer → reporter → user
                         (each step is a sub-agent invoked by the supervisor)
```

One pass per run. If the user changes the input or constraints mid-run, the supervisor restarts from preprocessing — no patching mid-pipeline.

## Directory layout

```
skills/                     # Agent skills (NemoClaw-compatible SKILL.md files)
scripts/                    # actual work: prepare.py, train.py, render_report.py
policy/                     # NemoClaw sandbox network policies (YAML)
data/raw/                   # client input lands here (read-only to agents)
data/clean/                 # preprocessor output: clean.parquet + profile.json
runs/queue/                 # architect drops candidate configs here
runs/results.tsv            # append-only ledger of every (config, metric) tuple
runs/live/best.json         # current best by primary metric
models/                     # trainer drops trained artifacts here
reports/final.md            # reporter output
```

## Who owns what

| Path | Read | Write | Append-only |
|---|---|---|---|
| `scripts/*.py` | all agents | **never** | n/a |
| `AGENTS.md` | all agents | **never** | n/a |
| `skills/*/SKILL.md` | all agents | **never** (humans curate skills) | n/a |
| `data/raw/` | preprocessor | **never** (read-only to all) | n/a |
| `data/clean/` | all downstream | preprocessor only | no |
| `runs/queue/` | trainer | architect only | no |
| `runs/results.tsv` | architect, trainer, reporter | trainer only | **yes — never rewrite past rows** |
| `runs/live/best.json` | reporter | trainer only | no (overwrite is fine) |
| `models/` | reporter | trainer only | no |
| `reports/final.md` | user | reporter only | no |

If a rule above conflicts with what your persona says, this table wins.

## Hand-off contract

Each stage's output is what the next stage reads. Filenames and formats are fixed.

| From | To | Artifact | Format |
|---|---|---|---|
| user | preprocessor | `data/raw/<anything>` | CSV / Excel / Parquet |
| preprocessor | architect | `data/clean/clean.parquet`, `data/clean/profile.json` | Parquet, JSON |
| architect | trainer | `runs/queue/*.json` (one file per config) | JSON, schema below |
| trainer | reporter | `runs/results.tsv`, `models/<run_id>.pkl` | TSV, pickle |
| reporter | user | `reports/final.md` | Markdown |

### `profile.json` schema

```json
{
  "rows": 12430,
  "cols": 27,
  "target": "churned",
  "target_type": "binary_classification",
  "class_balance": { "0": 0.83, "1": 0.17 },
  "dtypes": { "<col>": "int|float|category|datetime|text" },
  "missingness": { "<col>": 0.04 },
  "high_cardinality_cols": ["<col>", ...]
}
```

### `runs/queue/<run_id>.json` schema

```json
{
  "run_id": "2026-04-28T13-37_xgb_01",
  "model": "xgboost|lightgbm|catboost|logistic_regression",
  "params": { "max_depth": 6, "n_estimators": 500, "tree_method": "hist" },
  "primary_metric": "roc_auc|f1|rmse|...",
  "rationale": "one sentence from the architect"
}
```

### `runs/results.tsv` columns

```
run_id  model  primary_metric_name  primary_metric_value  secondary_metrics_json  duration_s  status  artifact_path
```

Append-only. `status` ∈ {`ok`, `failed`}. Never modify a past row, even to fix a typo — append a corrective row instead.

## Behavior rules

1. **Invoke scripts; do not reimplement.** Every agent's work routes through `scripts/prepare.py`, `scripts/train.py`, or `scripts/render_report.py`. Agents do not write training code in-line.
2. **Surface errors; do not retry blindly.** If a script exits non-zero, append a `status: failed` row with the stderr tail in `secondary_metrics_json` and stop. The supervisor decides whether to retry.
3. **One config per `runs/queue/` file.** The architect emits 2–3 files; the trainer processes each. No batched configs in one file.
4. **Stop when your output exists and is valid.** Do not "polish" finished artifacts. The next agent owns the next stage.
5. **Stay in your lane.** The architect does not preprocess. The trainer does not propose configs. The reporter does not retrain.
6. **No external HTTP unless your persona explicitly authorizes it.** OpenShell egress is allowlist-based; assume blocked by default.

## Memory vs. filesystem

- **Filesystem** — all artifacts (data, configs, models, reports). Anything that's an input or output of a script.
- **Hermes memory** — decisions and rationale. "Why CatBoost for low-cardinality retail data," "what worked last time on a similar profile." Use `memorySearch.write` and `memorySearch.read` for these. Files are for what scripts produce; memory is for what agents *learn*.

## Stop conditions

An agent stops and returns control to the supervisor when:

- Its expected input file is missing or malformed.
- A script it invoked exited non-zero.
- The work is complete and the next stage's expected input now exists.

Do not improvise around missing inputs. Surface and stop.
