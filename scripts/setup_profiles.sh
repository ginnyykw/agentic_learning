#!/usr/bin/env bash
# Create the four Hermes profiles for the tabular pipeline and copy in their personas.
# Idempotent: safe to re-run.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
HERMES_HOME="/sandbox"
PROFILES_DIR="$HERMES_HOME/.hermes/profiles"

# Sandbox names
PIPELINE_SB="data-pipeline"
REPORTER_SB="reporter"

ROLES=(preprocessor architect trainer reporter)

if ! command -v hermes >/dev/null 2>&1; then
  echo "error: hermes binary not found on PATH" >&2
  exit 1
fi

# Return 0 if Hermes already has this profile inside the sandbox (see: hermes profile list).
hermes_profile_exists() {
  local sb_name="$1" role="$2"
  openshell sandbox exec -n "$sb_name" bash -c \
    "hermes profile list 2>/dev/null | grep -q '^[ ◆]*${role} '"
}

for role in "${ROLES[@]}"; do
  # persona="$REPO_ROOT/skills/$role/SKILL.md"
  persona="$HERMES_HOME/skills/$role/SKILL.md"
  if [[ $role == "reporter" ]]; then
    sb_name=$REPORTER_SB
  else
    sb_name=$PIPELINE_SB
  fi

  #if [[ ! -f "$persona" ]]; then
  #  echo "error: missing skill $persona" >&2
  #  exit 1
  #fi

  profile_dir="$PROFILES_DIR/$role"
  if hermes_profile_exists "$sb_name" "$role"; then
    echo "[$role] profile exists — refreshing SOUL.md"
  else
    echo "[$role] creating profile"
    openshell sandbox exec -n "$sb_name" bash -c "hermes profile create $role"
  fi

  # Materialize the skill as the profile's SOUL.md.
  openshell sandbox exec -n $sb_name bash -c "cp "$persona" "$profile_dir/SOUL.md""
  # cp "$persona" "$profile_dir/SOUL.md"
  echo "[$role] SOUL.md ← skills/$role/SKILL.md"

  # Inherit model + API config from the default profile.
  # `hermes profile create` leaves these blank, so the new profile has no model.
  # We copy from $HERMES_HOME (the default profile's home) without touching it.
  for cfg in config.yaml .env; do
    src="$HERMES_HOME/.hermes/$cfg"
    dst="$profile_dir/$cfg"
    if [[ -f "$src" && ! -f "$dst" ]]; then
      openshell sandbox exec -n $sb_name bash -c "cp "$src" "$dst""
      # cp "$src" "$dst"
      echo "[$role] $cfg ← default"
    fi
  done
done

echo
echo "Done. Profiles ready:"
hermes profile list
echo
echo "Per-profile sanity check (optional): hermes -p <role> doctor"
