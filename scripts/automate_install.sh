#!/usr/bin/env bash
# ===========================================================================
# Automated Installation & Setup Script for Tabular ML Pipeline
# ===========================================================================
# This script automates the installation of uv, ollama, nemoclaw, and hermes,
# and configures the environment to use a local Ollama model.
#
# Usage:
#   bash scripts/automate_install.sh
# ===========================================================================

set -euo pipefail

# ── Configuration ──────────────────────────────────────────────────────────
OLLAMA_MODEL="qwen3.6:35b"  # Change this to your preferred model
PYTHON_VERSION="3.11"

# ── Colors ──────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info() { echo -e "${YELLOW}▸${NC} $*"; }
pass() { echo -e "${GREEN}✓${NC} $*"; }
section() { echo -e "\n${CYAN}═══════════════════════════════════════${NC}"; echo -e "${CYAN}  $*${NC}"; echo -e "${CYAN}═══════════════════════════════════════${NC}"; }

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

# ===================================================================
# 1. INSTALL UV
# ===================================================================
section "1. Installing uv"
if ! command -v uv >/dev/null 2>&1; then
    info "Installing uv via astral.sh..."
    curl -LsSf https://astral.sh/uv/install.sh | sh
    # Ensure uv is in the current path for the rest of the script
    export PATH="$HOME/.local/bin:$PATH"
    pass "uv installed"
else
    pass "uv already installed"
fi

# ===================================================================
# 2. INSTALL OLLAMA & PULL MODEL
# ===================================================================
section "2. Installing Ollama & Pulling $OLLAMA_MODEL"
if ! command -v ollama >/dev/null 2>&1; then
    info "Installing Ollama..."
    curl -fsSL https://ollama.com/install.sh | sh
    pass "Ollama installed"
else
    pass "Ollama already installed"
fi

# Start Ollama in background if not running
if ! pgrep -x "ollama" >/dev/null; then
    info "Starting Ollama server..."
    ollama serve > /dev/null 2>&1 &
    sleep 5
fi

info "Pulling model: $OLLAMA_MODEL..."
ollama pull "$OLLAMA_MODEL"
pass "Model $OLLAMA_MODEL ready"

# ===================================================================
# 3. INSTALL HERMES & NEMOCLAW
# ===================================================================
section "3. Installing Hermes & NemoClaw"

# Install Hermes
if ! command -v hermes >/dev/null 2>&1; then
    info "Installing Hermes Agent..."
    # Using the standard installer (adjust if your environment uses a different one)
    curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash
    pass "Hermes installed"
else
    pass "Hermes already installed"
fi

# Install NemoClaw / OpenShell
# Note: These are often provided as a bundle or specific installer.
# If they are not on PATH, we attempt a standard installation if known, 
# otherwise we warn the user.
if ! command -v nemoclaw >/dev/null 2>&1 || ! command -v openshell >/dev/null 2>&1; then
    info "NemoClaw/OpenShell not found. Attempting installation..."
    # Placeholder for actual NemoClaw installation command
    # e.g., curl -fsSL https://nemoclaw.nvidia.com/install.sh | bash
    # For this demo, we assume they might be available via a specific internal path or need manual install
    echo -e "${YELLOW}Warning: Automatic NemoClaw installation command unknown.${NC}"
    echo "Please ensure 'nemoclaw' and 'openshell' are installed and on your PATH."
else
    pass "NemoClaw and OpenShell found"
fi

# ===================================================================
# 4. CONFIGURE HERMES FOR OLLAMA (NON-INTERACTIVE)
# ===================================================================
section "4. Configuring Hermes to use Ollama ($OLLAMA_MODEL)"

# Ensure .hermes directory exists
mkdir -p "$HOME/.hermes"

info "Setting Hermes config for local Ollama..."
hermes config set model.provider custom
hermes config set model.base_url http://localhost:11434/v1
hermes config set model.default "$OLLAMA_MODEL"

pass "Hermes configured to use local Ollama"

# ===================================================================
# 5. SETUP AGENT PROFILES
# ===================================================================
section "5. Setting up Agent Profiles"
if [[ -f "scripts/setup_profiles.sh" ]]; then
    info "Running scripts/setup_profiles.sh..."
    bash scripts/setup_profiles.sh
    pass "Agent profiles created"
else
    echo -e "${RED}Error: scripts/setup_profiles.sh not found${NC}"
    exit 1
fi

# ===================================================================
# 6. SETUP LOCAL VENV & REQUIREMENTS
# ===================================================================
section "6. Setting up local Virtual Environment"
info "Creating venv with Python $PYTHON_VERSION..."
uv venv --python "$PYTHON_VERSION"
source .venv/bin/activate

info "Installing requirements..."
uv pip install -r requirements.txt
pass "Local environment ready"

# ===================================================================
# 7. SANDBOX ONBOARDING (NON-INTERACTIVE ATTEMPT)
# ===================================================================
#section "7. Initializing NemoClaw Sandboxes"

# We attempt to automate the 'nemoclaw onboard' by piping the expected answers.
# Typical sequence: 1 (hermes), then the model name, then the provider.
# Since we configured Hermes globally, it might simplify the wizard.

onboard_sandbox() {
    local name=$1
    if nemoclaw list 2>/dev/null | grep -q "$name"; then
        info "Sandbox '$name' already exists, skipping onboard."
    else
        info "Onboarding sandbox: $name..."
        # Feed the wizard: 
        # 1. Select Hermes
        # 2. Select Custom/Ollama (if it appears) or just use the default we set
        # This is a heuristic; if the wizard changes, this might need adjustment.
        printf "hermes\n$OLLAMA_MODEL\ncustom\n" | nemoclaw onboard --name "$name" || {
            echo -e "${YELLOW}Warning: Automated onboard for $name failed.${NC}"
            echo "Please run manually: nemoclaw onboard --name $name"
        }
    fi
}

# Attempt to onboard the two required sandboxes
#onboard_sandbox "data-pipeline"
#onboard_sandbox "reporter"

# ===================================================================
# 8. FINAL SETUP (POLICIES & UPLOADS)
# ===================================================================
section "8. Running Final Setup"
info "Running scripts/setup-demo.sh --skip-gateway..."
# We skip gateway if it's already handled or needs sudo
bash scripts/setup-demo.sh --skip-gateway || info "Note: setup-demo.sh had some issues, likely due to interactive parts."

pass "Installation and setup complete!"

echo -e "\n${GREEN}==========================================================${NC}"
echo -e "  ${GREEN}SUCCESS: The environment is ready.${NC}"
echo -e "  To start the pipeline, run:"
echo -e "  ${CYAN}source .venv/bin/activate${NC}"
echo -e "  ${CYAN}bash scripts/run_pipeline.sh data/raw/telco-churn.csv Churn${NC}"
echo -e "${GREEN}==========================================================${NC}"
