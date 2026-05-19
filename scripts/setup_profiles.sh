#!/usr/bin/env bash
# Create the four Hermes profiles for the tabular pipeline and copy in their personas.
# Idempotent: safe to re-run.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
PROFILES_DIR="$HERMES_HOME/profiles"

ROLES=(preprocessor architect trainer reporter orchestrator)

if ! command -v hermes >/dev/null 2>&1; then
  echo "error: hermes binary not found on PATH" >&2
  exit 1
fi

for role in "${ROLES[@]}"; do
  persona="$REPO_ROOT/skills/$role/SKILL.md"
  if [[ ! -f "$persona" ]]; then
    echo "error: missing skill $persona" >&2
    exit 1
  fi

  profile_dir="$PROFILES_DIR/$role"
  if [[ -d "$profile_dir" ]]; then
    echo "[$role] profile exists — refreshing SOUL.md"
  else
    echo "[$role] creating profile"
    hermes profile create "$role"
  fi

  # Materialize the skill as the profile's SOUL.md.
  cp "$persona" "$profile_dir/SOUL.md"
  echo "[$role] SOUL.md ← skills/$role/SKILL.md"

  # Inherit model + API config from the default profile.
  # `hermes profile create` leaves these blank, so the new profile has no model.
  # We copy from $HERMES_HOME (the default profile's home) without touching it.
  for cfg in config.yaml .env; do
    src="$HERMES_HOME/$cfg"
    dst="$profile_dir/$cfg"
    if [[ -f "$src" && ! -f "$dst" ]]; then
      cp "$src" "$dst"
      echo "[$role] $cfg ← default"
    fi
  done
done

echo
echo "Done. Profiles ready:"
hermes profile list
echo
echo "Per-profile sanity check (optional): hermes -p <role> doctor"
