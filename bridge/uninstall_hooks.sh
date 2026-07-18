#!/usr/bin/env bash
#
# uninstall_hooks.sh — safely remove the Khosrow Claude Code hooks.
#
# Removes ONLY the pet's hook entries from settings.json (identified by their
# marker), leaving every other setting and hook untouched. Backs up first.
#
# Usage:
#   ./uninstall_hooks.sh              # remove hooks (with confirmation)
#   ./uninstall_hooks.sh --dry-run    # preview cleaned settings, write nothing
#   ./uninstall_hooks.sh --yes        # skip confirmation
#   ./uninstall_hooks.sh --purge      # also delete ~/.claude-pet (bridge + state)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
SETTINGS="$CLAUDE_DIR/settings.json"
PET_DIR="$HOME/.claude-pet"
BRIDGE_DEST="$PET_DIR/bridge"
PYTHON="${KHOSROW_PYTHON:-python3}"

DRY_RUN=0
ASSUME_YES=0
PURGE=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --yes|-y)  ASSUME_YES=1 ;;
    --purge)   PURGE=1 ;;
    *) echo "Unknown option: $arg" >&2; exit 2 ;;
  esac
done

command -v "$PYTHON" >/dev/null 2>&1 || { echo "python3 not found" >&2; exit 1; }

# Prefer the installed merge utility; fall back to the repo copy.
MERGE_TOOL="$BRIDGE_DEST/khosrow_pet/settings_merge.py"
[[ -f "$MERGE_TOOL" ]] || MERGE_TOOL="$SCRIPT_DIR/khosrow_pet/settings_merge.py"

if [[ ! -f "$SETTINGS" ]]; then
  echo "No settings file at $SETTINGS — nothing to remove."
else
  if [[ "$DRY_RUN" == "0" && "$ASSUME_YES" == "0" ]]; then
    read -r -p "Remove Khosrow hooks from $SETTINGS? [y/N] " reply
    [[ "$reply" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }
  fi

  if [[ "$DRY_RUN" == "1" ]]; then
    echo "--- cleaned settings.json (dry run) ---"
    "$PYTHON" "$MERGE_TOOL" remove --settings "$SETTINGS" --dry-run
  else
    "$PYTHON" "$MERGE_TOOL" remove --settings "$SETTINGS"
    echo "Removed Khosrow hooks (backup written next to settings.json)."
  fi
fi

if [[ "$PURGE" == "1" && "$DRY_RUN" == "0" ]]; then
  rm -rf "$PET_DIR"
  echo "Purged $PET_DIR"
fi

echo "Restart any running Claude Code sessions so hooks reload."
