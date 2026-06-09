#!/usr/bin/env bash
# Run the full four-stage pipeline by invoking the orchestrator agent.
# The orchestrator spawns preprocessor → architect → trainer → reporter and
# verifies hand-off artifacts between stages.
#
# Usage:
#   bash scripts/run_pipeline.sh [<input>] [<target>]
#
# Defaults: data/raw/telco-churn.csv, target=Churn

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

INPUT="${1:-data/raw/telco-churn.csv}"
TARGET="${2:-Churn}"

# Sanity: the agents shell out to scripts/py, which resolves to .venv/bin/python.
# The orchestrator inherits our shell, so confirm the venv exists before we hand off.
#if [[ ! -x .venv/bin/python ]]; then
#  echo "error: .venv/bin/python is missing" >&2
#  echo "  fix: uv venv --python 3.11 && source .venv/bin/activate && uv pip install -r requirements.txt" >&2
#  exit 1
#fi

# Activate venv (no-op if scripts/py already absolutizes, but harmless and helps any
# operator-level tooling that does rely on the venv being on PATH).
#if [[ -z "${VIRTUAL_ENV:-}" ]]; then
#  # shellcheck disable=SC1091
#  source .venv/bin/activate
#fi

#if ! hermes profile list 2>/dev/null | grep -q '^[ ◆]*orchestrator '; then
#  echo "error: hermes profile 'orchestrator' not found" >&2
#  echo "  fix: bash scripts/setup_profiles.sh" >&2
#  exit 1
#fi

echo "=========================================================="
echo "  preprocessor pipeline"
echo "  input:  $INPUT"
echo "  target: $TARGET"
echo "=========================================================="
date

openshell sandbox exec -n data-pipeline bash -c "hermes -p preprocessor chat -t terminal,file \
-q "Process $INPUT with target=$TARGET" --yolo"


echo "=========================================================="
echo "  architect pipeline"
echo "=========================================================="
date

openshell sandbox exec -n data-pipeline bash -c "hermes -p architect chat -t file \
-q "Read data/clean/profile.json and queue 2-3 configs" --yolo"

echo "=========================================================="
echo "  trainer pipeline"
echo "=========================================================="
date

openshell sandbox exec -n data-pipeline bash -c "hermes -p trainer chat -t terminal,file \
-q "Train runs/queue/" --yolo"


echo "=========================================================="
echo "  Downloading results from data-pipeline"
echo "=========================================================="
date

DOWNLOAD_RPT=(
    "/sandbox/runs/live/best.json:$REPO_ROOT/runs/live/best.json"
    "/sandbox/runs/results.tsv:$REPO_ROOT/runs/results.tsv"
    "/sandbox/data/clean/profile.json:$REPO_ROOT/data/clean/profile.json"
    "/sandbox/models/:$REPO_ROOT/models"
)

for download in "${DOWNLOAD_RPT[@]}"; do
    local_src="${download%%:*}"
    remote_dst="${download##*:}"
    echo "Downloading $local_src -> $remote_dst"
    openshell sandbox download data-pipeline $local_src $remote_dst
done

# cp -r "$REPO_ROOT/runs" "$REPO_ROOT/runs1"
# cp -r "$REPO_ROOT/models" "$REPO_ROOT/models1"
# cp -r "$REPO_ROOT/data/clean/" "$REPO_ROOT/data1"


echo
echo "=========================================================="
echo "  DONE for data-pipeline"
echo "=========================================================="
date