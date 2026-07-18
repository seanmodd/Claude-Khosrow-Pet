#!/usr/bin/env bash
#
# install_hooks.sh — safely install the Khosrow Claude Code hooks.
#
# What it does (and ONLY this):
#   1. Copies the bridge into ~/.claude-pet/bridge
#   2. Timestamped-backs-up your existing Claude settings.json
#   3. MERGES the pet hooks into settings.json (never overwrites; idempotent)
#
# It never touches your source repos, never edits Claude Desktop, and only ever
# adds the eight documented hook entries. Re-running refreshes, doesn't stack.
#
# Usage:
#   ./install_hooks.sh              # install (with confirmation)
#   ./install_hooks.sh --dry-run    # print the merged settings, write nothing
#   ./install_hooks.sh --yes        # skip the confirmation prompt
#
# Safety: refuses to run on non-macOS unless KHOSROW_ALLOW_NON_MACOS=1 is set,
# so it can't be run by accident inside a Linux CI/cloud environment.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
SETTINGS="$CLAUDE_DIR/settings.json"
PET_DIR="$HOME/.claude-pet"
BRIDGE_DEST="$PET_DIR/bridge"
PYTHON="${KHOSROW_PYTHON:-python3}"

DRY_RUN=0
ASSUME_YES=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --yes|-y)  ASSUME_YES=1 ;;
    *) echo "Unknown option: $arg" >&2; exit 2 ;;
  esac
done

# --- safety: macOS only (unless explicitly overridden) ----------------------
if [[ "$(uname -s)" != "Darwin" && "${KHOSROW_ALLOW_NON_MACOS:-0}" != "1" ]]; then
  echo "Refusing to install on non-macOS ($(uname -s))." >&2
  echo "This installer is for your Mac. Set KHOSROW_ALLOW_NON_MACOS=1 to force." >&2
  exit 1
fi

command -v "$PYTHON" >/dev/null 2>&1 || { echo "python3 not found" >&2; exit 1; }

echo "Khosrow hook installer"
echo "  Claude settings : $SETTINGS"
echo "  Bridge install  : $BRIDGE_DEST"
echo "  State file      : $PET_DIR/state.json"
echo

if [[ "$DRY_RUN" == "0" && "$ASSUME_YES" == "0" ]]; then
  read -r -p "Proceed with install? [y/N] " reply
  [[ "$reply" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }
fi

# --- 1. copy the bridge ------------------------------------------------------
if [[ "$DRY_RUN" == "0" ]]; then
  mkdir -p "$BRIDGE_DEST"
  cp -R "$SCRIPT_DIR/khosrow_pet" "$BRIDGE_DEST/"
  cp "$SCRIPT_DIR/khosrow_pet_hook.py" "$BRIDGE_DEST/"
  cp "$SCRIPT_DIR/simulate_events.py" "$SCRIPT_DIR/simulate_states.py" "$BRIDGE_DEST/"
  echo "Copied bridge to $BRIDGE_DEST"
fi

# --- 2 + 3. backup + merge settings -----------------------------------------
MERGE_ARGS=(install --settings "$SETTINGS" --bridge-dir "$BRIDGE_DEST" --python "$PYTHON")
if [[ "$DRY_RUN" == "1" ]]; then
  echo "--- merged settings.json (dry run, nothing written) ---"
  "$PYTHON" "$SCRIPT_DIR/khosrow_pet/settings_merge.py" "${MERGE_ARGS[@]}" --dry-run
else
  mkdir -p "$CLAUDE_DIR"
  "$PYTHON" "$BRIDGE_DEST/khosrow_pet/settings_merge.py" "${MERGE_ARGS[@]}"
  echo
  echo "Done. Restart any running Claude Code sessions so hooks reload."
  echo "Launch the pet, then try:  python3 $BRIDGE_DEST/simulate_states.py --cycle"
fi
