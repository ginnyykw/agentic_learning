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
if [[ ! -x .venv/bin/python ]]; then
  echo "error: .venv/bin/python is missing" >&2
  echo "  fix: uv venv --python 3.11 && source .venv/bin/activate && uv pip install -r requirements.txt" >&2
  exit 1
fi

# Activate venv (no-op if scripts/py already absolutizes, but harmless and helps any
# operator-level tooling that does rely on the venv being on PATH).
if [[ -z "${VIRTUAL_ENV:-}" ]]; then
  # shellcheck disable=SC1091
  source .venv/bin/activate
fi

if ! hermes profile list 2>/dev/null | grep -q '^[ ◆]*orchestrator '; then
  echo "error: hermes profile 'orchestrator' not found" >&2
  echo "  fix: bash scripts/setup_profiles.sh" >&2
  exit 1
fi

echo "=========================================================="
echo "  orchestrator pipeline"
echo "  input:  $INPUT"
echo "  target: $TARGET"
echo "=========================================================="
date

hermes -p orchestrator chat -t terminal,file \
  -q "Process $INPUT with target=$TARGET" --yolo

date
echo
echo "=========================================================="
echo "  DONE"
echo "=========================================================="
ls -la reports/ 2>/dev/null || echo "(no reports/)"
