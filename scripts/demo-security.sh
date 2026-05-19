#!/usr/bin/env bash
# Demo script: show the power of the NemoClaw YAML policy.
# Run this on stage to demonstrate sandbox security.
#
# Prerequisites:
#   - data-pipeline sandbox running with policy applied
#   - reporter sandbox running with policy applied
#   - Files uploaded to each sandbox (see setup-demo.sh)

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

pass()  { echo -e "  ${GREEN}✓ PASS${NC}   $*"; }
fail()  { echo -e "  ${RED}✗ BLOCKED${NC}  $*" ; }
info()  { echo -e "  ${YELLOW}▸${NC} $*"; }
section() { echo -e "\n${CYAN}═══════════════════════════════════════${NC}"; echo -e "${CYAN}  $*${NC}"; echo -e "${CYAN}═══════════════════════════════════════${NC}"; }

# ── Section 1: Network Policy ──────────────────────────────────────────────

section "1. Network Policy — what can each sandbox reach?"

info "Reporter sandbox: trying to reach the internet..."
OUT=$(openshell sandbox exec -n reporter curl -s --connect-timeout 3 ifconfig.me 2>&1 || true)
if echo "$OUT" | grep -q "policy_denied"; then
  fail "curl ifconfig.me → policy_denied (blocked by YAML)"
else
  pass "curl ifconfig.me → unexpected response: $OUT"
fi

info "Reporter sandbox: trying to reach GitHub..."
OUT=$(openshell sandbox exec -n reporter curl -sk --connect-timeout 3 https://github.com 2>&1 || true)
if [ -z "$OUT" ] || echo "$OUT" | grep -q "policy_denied\|error:56\|Connection refused"; then
  fail "curl github.com → blocked (no network_policies in YAML)"
else
  pass "curl github.com → unexpected: $OUT"
fi

info "data-pipeline sandbox: trying to reach GitHub..."
OUT=$(openshell sandbox exec -n data-pipeline curl -sk --connect-timeout 3 https://github.com 2>&1 || true)
if [ -z "$OUT" ] || echo "$OUT" | grep -q "policy_denied\|error:56\|Connection refused"; then
  fail "curl github.com → blocked (only NVIDIA inference allowed)"
else
  pass "curl github.com → unexpected: $OUT"
fi

info "data-pipeline sandbox: trying NVIDIA inference (inference.local)..."
OUT=$(openshell sandbox exec -n data-pipeline curl -sk --connect-timeout 3 https://inference.local/v1/models 2>&1 || true)
if echo "$OUT" | grep -q '"object":"list"'; then
  pass "curl inference.local/v1/models → 200 OK (allowed by YAML)"
else
  fail "curl inference.local → unexpected: $OUT"
fi

# ── Section 2: Filesystem Policy (Landlock) ────────────────────────────────

section "2. Filesystem Policy — where can each sandbox write?"

info "Reporter sandbox: trying to write to /etc (protected)..."
OUT=$(openshell sandbox exec -n reporter touch /etc/testfile 2>&1 || true)
if echo "$OUT" | grep -q "Permission denied"; then
  fail "touch /etc/testfile → Permission denied (Landlock enforced)"
else
  pass "touch /etc/testfile → unexpected: $OUT"
fi

info "Reporter sandbox: trying to write to /usr (protected)..."
OUT=$(openshell sandbox exec -n reporter touch /usr/local/bin/testfile 2>&1 || true)
if echo "$OUT" | grep -q "Permission denied"; then
  fail "touch /usr/local/bin/testfile → Permission denied (Landlock)"
else
  pass "touch /usr/local/bin/testfile → unexpected: $OUT"
fi

info "Reporter sandbox: writing to /sandbox (allowed)..."
openshell sandbox exec -n reporter touch /sandbox/test_ok 2>&1 >/dev/null
openshell sandbox exec -n reporter rm -f /sandbox/test_ok 2>&1 >/dev/null
pass "touch /sandbox/test_ok → success (read_write: /sandbox)"

# ── Section 3: Process Isolation ───────────────────────────────────────────

section "3. Process Isolation — who runs inside the sandbox?"

OUT=$(openshell sandbox exec -n reporter whoami 2>&1)
if [ "$OUT" = "sandbox" ]; then
  pass "whoami → $OUT (unprivileged user, not root)"
else
  fail "whoami → $OUT (expected: sandbox)"
fi

OUT=$(openshell sandbox exec -n data-pipeline whoami 2>&1)
if [ "$OUT" = "sandbox" ]; then
  pass "whoami in data-pipeline → $OUT (unprivileged user)"
else
  fail "whoami → $OUT (expected: sandbox)"
fi

# ── Section 4: Sandbox Isolation (Data Separation) ────────────────────────

section "4. Sandbox Isolation — what data can each sandbox see?"

info "data-pipeline sandbox: listing /sandbox/data/raw/..."
OUT=$(openshell sandbox exec -n data-pipeline ls /sandbox/data/raw/ 2>&1 || true)
if echo "$OUT" | grep -q "telco-churn.csv"; then
  pass "ls /sandbox/data/raw/ → telco-churn.csv (data exists here)"
else
  fail "ls /sandbox/data/raw/ → $OUT (expected telco-churn.csv)"
fi

info "Reporter sandbox: trying to access /sandbox/data/raw/..."
OUT=$(openshell sandbox exec -n reporter ls /sandbox/data/raw/ 2>&1 || true)
if echo "$OUT" | grep -q "No such file or directory\|cannot access"; then
  fail "ls /sandbox/data/raw/ → No such file (reporter has NO raw data)"
else
  pass "ls /sandbox/data/raw/ → $OUT (unexpected)"
fi

# ── Section 5: Policy Versioning ───────────────────────────────────────────

section "5. Policy Versioning — live updates without restart"

info "data-pipeline policy version:"
openshell policy get data-pipeline 2>&1 | grep "Active:"

info "Reporter policy version:"
openshell policy get reporter 2>&1 | grep "Active:"

info "Policy files on disk:"
ls -1 "$(dirname "$0")/../policy/"

# ── Summary ────────────────────────────────────────────────────────────────

section "Summary"

cat <<'EOF'
  ┌─────────────────┬──────────────────┬──────────────────┐
  │                 │ data-pipeline    │ reporter         │
  ├─────────────────┼──────────────────┼──────────────────┤
  │ Network         │ nvidia + local   │ NONE             │
  │ Filesystem      │ /sandbox r/w     │ /sandbox r/w     │
  │ User            │ sandbox (no root)│ sandbox (no root)│
  │ Has raw data?   │ YES              │ NO               │
  │ Agents          │ preprocessor,    │ reporter         │
  │                 │ architect,trainer│                  │
  └─────────────────┴──────────────────┴──────────────────┘

  YAML policy files:
    policy/demo-pipeline-restricted.yaml  → data-pipeline policy
    policy/reporter-restricted.yaml       → reporter policy (zero network)

  To modify a policy:
    1. Edit the YAML file
    2. openshell policy set --policy <file> <sandbox> --wait
    3. Changes take effect immediately (no restart)
EOF

echo ""
echo "Demo complete."
