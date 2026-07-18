#!/usr/bin/env python3
"""Claude Code hook entry point for the Khosrow pet.

Registered in ~/.claude/settings.json for each lifecycle event. On every event
it reads the raw hook JSON from stdin, reduces it to a minimal, non-sensitive
summary (state / toolCategory / timestamp / success), and emits that to the pet
via the state file and the optional localhost listener.

Robustness contract: this must NEVER block or break Claude Code. Any error is
swallowed and the process exits 0.

Privacy contract: only the coarse summary leaves this process. Prompts, source
code, file contents, command strings, credentials, and secrets are never read
into the payload (see khosrow_pet.core.redact).
"""
from __future__ import annotations

import argparse
import json
import os
import sys

# Import the shared core whether we're run as an installed script or in-repo.
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
try:
    from khosrow_pet import core
except Exception:  # pragma: no cover - defensive; never break Claude Code
    sys.exit(0)


def main() -> int:
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("--event", default=None,
                        help="Lifecycle event name (else read from stdin).")
    parser.add_argument("--http-port", type=int,
                        default=int(os.environ.get("KHOSROW_PET_HTTP_PORT", "51763")))
    parser.add_argument("--no-http", action="store_true")
    args, _ = parser.parse_known_args()

    # Parse stdin defensively; missing/invalid stdin is fine.
    raw = ""
    try:
        if not sys.stdin.isatty():
            raw = sys.stdin.read()
    except Exception:
        raw = ""
    try:
        hook_input = json.loads(raw) if raw.strip() else {}
        if not isinstance(hook_input, dict):
            hook_input = {}
    except Exception:
        hook_input = {}

    safe = core.redact(hook_input, event_override=args.event)
    state = core.map_state(safe["event"], safe["category"], safe["success"])
    payload = core.build_payload(state, safe["category"], safe["success"])

    core.emit(payload, http_port=None if args.no_http else args.http_port)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception:
        # Absolutely never propagate an error back to Claude Code.
        sys.exit(0)
