#!/usr/bin/env bash
# ===========================================================================
# Agentic Learning Series Demo — Full Setup Script
# ===========================================================================
# Sets up both NemoClaw sandboxes (data-pipeline + reporter) from scratch:
#   1. Ensures OpenShell gateway is running
#   2. Creates both sandboxes via nemoclaw onboard
#   3. Applies YAML network policies
#   4. Uploads data, scripts, agents and AGENTS.md to each sandbox
#   5. Installs Python dependencies inside each sandbox
#   6. Sets up local Hermes profiles (for pipeline run on host)
#   7. Verifies everything is ready
#
# Usage:
#   bash scripts/setup-demo.sh           # full setup (idempotent)
#   bash scripts/setup-demo.sh --skip-gateway   # skip gateway start
#   bash scripts/setup-demo.sh --dry-run  # show commands without running
#
# Prerequisites:
#   - OpenShell installed (openshell binary on PATH)
#   - NemoClaw installed (nemoclaw binary on PATH)
#   - Hermes installed (hermes binary on PATH)
#   - NVIDIA inference API key configured in ~/.nemoclaw/credentials.json
#   - Docker running
# ===========================================================================

set -euo pipefail

# ── Colors ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

pass()  { echo -e "  ${GREEN}✓${NC} $*"; }
fail()  { echo -e "  ${RED}✗${NC} $*"; return 1; }
info()  { echo -e "  ${YELLOW}▸${NC} $*"; }
section() { echo -e "\n${CYAN}═══════════════════════════════════════${NC}"; echo -e "${CYAN}  $*${NC}"; echo -e "${CYAN}═══════════════════════════════════════${NC}"; }

# ── Config ──────────────────────────────────────────────────────────────────
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DRY_RUN="${DRY_RUN:-0}"
SKIP_GATEWAY="${SKIP_GATEWAY:-0}"

# Sandbox names
PIPELINE_SB="data-pipeline"
REPORTER_SB="reporter"

# Policy files
PIPELINE_POLICY="$REPO_ROOT/policy_new/demo-pipeline-restricted.yaml"
REPORTER_SETUP_POLICY="$REPO_ROOT/policy_new/reporter-setup.yaml"
REPORTER_POLICY="$REPO_ROOT/policy_new/reporter-restricted.yaml"

# ── Helpers ─────────────────────────────────────────────────────────────────
run() {
    if [[ "$DRY_RUN" == "1" ]]; then
        echo "  [DRY RUN] $*"
    else
        eval "$*"
    fi
}

check_cmd() {
    if ! command -v "$1" >/dev/null 2>&1; then
        fail "'$1' not found on PATH"
        return 1
    fi
}

sandbox_exists() {
    nemoclaw list 2>/dev/null | grep -q "$1"
}

# ── Parse args ─────────────────────────────────────────────────────────────
for arg in "$@"; do
    case "$arg" in
        --dry-run)     DRY_RUN=1 ;;
        --skip-gateway) SKIP_GATEWAY=1 ;;
    esac
done

if [[ "$DRY_RUN" == "1" ]]; then
    echo -e "${YELLOW}DRY RUN MODE — commands shown but not executed${NC}"
fi

# ===================================================================
# PREREQUISITES
# ===================================================================
section "1. Checking prerequisites"

check_cmd openshell   || exit 1
check_cmd nemoclaw    || exit 1
check_cmd hermes      || exit 1
pass "All required binaries found"

# Verify policy files exist
for pf in "$PIPELINE_POLICY" "$REPORTER_POLICY"; do
    if [[ ! -f "$pf" ]]; then
        fail "Policy file not found: $pf"
        exit 1
    fi
done
pass "Policy files found"

# Verify required repo files exist
REQUIRED_FILES=(
    "data/raw/telco-churn.csv"
    "scripts/prepare.py"
    "scripts/train.py"
    "scripts/render_report.py"
    "scripts/demo-security.sh"
    "skills/preprocessor/SKILL.md"
    "skills/architect/SKILL.md"
    "skills/trainer/SKILL.md"
    "skills/reporter/SKILL.md"
    "AGENTS.md"
    "requirements.txt"
)

for rf in "${REQUIRED_FILES[@]}"; do
    if [[ ! -f "$REPO_ROOT/$rf" ]]; then
        fail "Required file missing: $rf"
        exit 1
    fi
done
pass "All required repo files present"

# ===================================================================
# GATEWAY
# ===================================================================
if [[ "$SKIP_GATEWAY" == "0" ]]; then
    section "2. Starting OpenShell gateway"

    if openshell gateway status >/dev/null 2>&1; then
        pass "Gateway already running"
    else
        info "Starting gateway..."
        run "openshell gateway start"
        sleep 3
        pass "Gateway started"
    fi
else
    section "2. Skipping gateway (already running)"
fi

# ===================================================================
# CREATE DATA-PIPELINE SANDBOX
# ===================================================================
section "3. Creating $PIPELINE_SB sandbox"

if sandbox_exists "$PIPELINE_SB"; then
    info "$PIPELINE_SB already exists — recreating..."
    if [[ "$DRY_RUN" == "0" ]]; then
        echo "nemoclaw $PIPELINE_SB destroy --yes" | bash 2>/dev/null || true
        sleep 2
    fi
fi

info "Onboarding $PIPELINE_SB..."
info "Running: nemoclaw onboard --agent hermes --name $PIPELINE_SB"
info "  When prompted:"
info "    Agent: hermes"
info "    Model: nvidia/nemotron-3-super-120b-a12b"
info "    Inference: NVIDIA prod"
echo

# This step is interactive — the wizard needs user input
if [[ "$DRY_RUN" == "1" ]]; then
    echo "  [DRY RUN] nemoclaw onboard --name $PIPELINE_SB"
    echo "  [DRY RUN] (wizard: agent=hermes, model=nvidia/nemotron-3-super-120b-a12b, provider=nvidia-prod)"
else
    # If there's no TTY, we can't run the interactive wizard
    if [[ ! -t 0 ]]; then
        echo -e "${YELLOW}WARNING: No TTY detected — cannot run interactive wizard${NC}"
        echo "Run this script from an interactive terminal, or create the sandbox manually:"
        echo "  nemoclaw onboard --name $PIPELINE_SB"
        echo "  Then follow the wizard prompts."
        exit 1
    fi
    nemoclaw onboard --agent hermes --name "$PIPELINE_SB"
fi

pass "$PIPELINE_SB created"

# ===================================================================
# CREATE REPORTER SANDBOX
# ===================================================================
section "4. Creating $REPORTER_SB sandbox"

if sandbox_exists "$REPORTER_SB"; then
    info "$REPORTER_SB already exists — recreating..."
    if [[ "$DRY_RUN" == "0" ]]; then
        echo "nemoclaw $REPORTER_SB destroy --yes" | bash 2>/dev/null || true
        sleep 2
    fi
fi

info "Onboarding $REPORTER_SB..."
info "Running: nemoclaw onboard --agent hermes --name $REPORTER_SB"
info "  When prompted:"
info "    Agent: hermes"
info "    Model: nvidia/nemotron-3-super-120b-a12b"
info "    Inference: NVIDIA prod"
echo

if [[ "$DRY_RUN" == "1" ]]; then
    echo "  [DRY RUN] nemoclaw onboard --name $REPORTER_SB"
    echo "  [DRY RUN] (wizard: agent=hermes, model=nvidia/nemotron-3-super-120b-a12b, provider=nvidia-prod)"
else
    if [[ ! -t 0 ]]; then
        echo -e "${YELLOW}WARNING: No TTY detected — cannot run interactive wizard${NC}"
        exit 1
    fi
    nemoclaw onboard --agent hermes --name "$REPORTER_SB"
fi

pass "$REPORTER_SB created"

# ===================================================================
# APPLY NETWORK POLICIES
# ===================================================================
section "5. Applying network policies"

info "Removing default presets from $PIPELINE_SB..."
for preset in npm pypi huggingface brew brave github; do
    run "echo '' | nemoclaw $PIPELINE_SB policy-remove --yes 2>/dev/null <<< '$preset'" || true
done

info "Applying $PIPELINE_SB policy: demo-pipeline-restricted.yaml"
run "openshell policy set --policy $PIPELINE_POLICY $PIPELINE_SB --wait"
pass "$PIPELINE_SB policy applied (NVIDIA inference + local gateway only)"

info "Removing default presets from $REPORTER_SB..."
for preset in npm pypi huggingface brew brave github; do
    run "echo '' | nemoclaw $REPORTER_SB policy-remove --yes 2>/dev/null <<< '$preset'" || true
done

info "Applying $REPORTER_SB policy: reporter-setup.yaml"
run "openshell policy set --policy $REPORTER_SETUP_POLICY $REPORTER_SB --wait"

# Install Python deps in reporter
info "Installing Python dependencies in $REPORTER_SB..."
run "openshell sandbox exec -n $REPORTER_SB bash -c 'python3 -m venv /sandbox/.venv && /sandbox/.venv/bin/pip install pandas pyarrow openpyxl'"
pass "Python deps installed in $REPORTER_SB"

info "Removing default presets from $REPORTER_SB..."
for preset in npm pypi huggingface brew brave github; do
    run "echo '' | nemoclaw $REPORTER_SB policy-remove --yes 2>/dev/null <<< '$preset'" || true
done

info "Applying $REPORTER_SB policy: reporter-restricted.yaml"
run "openshell policy set --policy $REPORTER_POLICY $REPORTER_SB --wait"
pass "$REPORTER_SB policy applied (ZERO network)"

# ===================================================================
# UPLOAD FILES TO DATA-PIPELINE SANDBOX
# ===================================================================
section "6. Uploading files to $PIPELINE_SB"

UPLOAD_PIPE=(
    "data/raw/telco-churn.csv:/sandbox/data/raw"
    "scripts/prepare.py:/sandbox/scripts"
    "scripts/train.py:/sandbox/scripts"
    "skills/preprocessor/SKILL.md:/sandbox/skills/preprocessor"
    "skills/architect/SKILL.md:/sandbox/skills/architect"
    "skills/trainer/SKILL.md:/sandbox/skills/trainer"
    "AGENTS.md:/sandbox"
)

for upload in "${UPLOAD_PIPE[@]}"; do
    local_src="${upload%%:*}"
    remote_dst="${upload##*:}"
    info "Uploading $local_src -> $remote_dst"
    run "openshell sandbox upload $PIPELINE_SB $REPO_ROOT/$local_src $remote_dst"
done

pass "All files uploaded to $PIPELINE_SB"

# Install Python deps in data-pipeline
info "Installing Python dependencies in $PIPELINE_SB..."
run "openshell sandbox exec -n $PIPELINE_SB bash -c 'python3 -m venv /sandbox/.venv && /sandbox/.venv/bin/pip install pandas pyarrow scikit-learn xgboost openpyxl'"
pass "Python deps installed in $PIPELINE_SB"

# ===================================================================
# UPLOAD FILES TO REPORTER SANDBOX
# ===================================================================
section "7. Uploading files to $REPORTER_SB"

UPLOAD_RPT=(
    "scripts/render_report.py:/sandbox/scripts"
    "skills/reporter/SKILL.md:/sandbox/skills/reporter"
    "AGENTS.md:/sandbox"
)

for upload in "${UPLOAD_RPT[@]}"; do
    local_src="${upload%%:*}"
    remote_dst="${upload##*:}"
    info "Uploading $local_src -> $remote_dst"
    run "openshell sandbox upload $REPORTER_SB $REPO_ROOT/$local_src $remote_dst"
done

pass "All files uploaded to $REPORTER_SB"

# ===================================================================
# SETUP LOCAL HERMES PROFILES
# ===================================================================
section "8. Setting up local Hermes profiles"

info "Running setup_profiles.sh..."
run "bash $REPO_ROOT/scripts/setup_profiles.sh"
pass "Hermes profiles configured"

# ===================================================================
# VERIFY
# ===================================================================
section "9. Verification"

info "Checking sandbox status..."
if [[ "$DRY_RUN" == "0" ]]; then
    nemoclaw list
    echo

    info "Checking $PIPELINE_SB policy..."
    openshell policy get "$PIPELINE_SB" | grep "Active:"

    info "Checking $REPORTER_SB policy..."
    openshell policy get "$REPORTER_SB" | grep "Active:"
    echo
fi

# ===================================================================
# SUMMARY
# ===================================================================
section "Setup Complete"

cat <<'EOF'

  The demo is ready! Here's what was set up:

  Sandboxes:
    data-pipeline    → NVIDIA inference only (blocked: everything else)
    reporter         → ZERO network (completely blocked)

  Files uploaded:
    data-pipeline: telco-churn.csv, prepare.py, train.py,
                   skills/preprocessor/SKILL.md, skills/architect/SKILL.md,
                   skills/trainer/SKILL.md, AGENTS.md
    reporter:      render_report.py, skills/reporter/SKILL.md, AGENTS.md

  Next steps:
    1. Run the pipeline:
       bash scripts/run_pipeline.sh data/raw/telco-churn.csv Churn

    2. Upload results to reporter:

       openshell sandbox upload reporter runs/results.tsv /sandbox/runs
       openshell sandbox upload reporter runs/live/best.json /sandbox/runs/live
       openshell sandbox upload reporter models/*.pkl /sandbox/models
       openshell sandbox upload reporter data/clean/profile.json /sandbox/data/clean

    3. Run reporter:
       openshell sandbox exec -n data-pipeline bash -c "hermes -p reporter chat -t terminal,file \
       -q "Render the final report" --yolo"

    4. Download report:
       openshell sandbox download reporter /sandbox/reports/final.md reports/final.md

    5. Run security demo:
       bash scripts/demo-security.sh

  Diagram:
    https://excalidraw.com/#json=Bp6Up7SZu4rN21cpMA5Yo,9etHITeVufwTQLsh_g7Yow
EOF
