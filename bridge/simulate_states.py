#!/usr/bin/env python3
"""Pet-state simulator.

Directly drives the pet through states by writing the state file (and optional
localhost POST) — no Claude Code and no hook payloads involved. Handy for
eyeballing every animation on a real Mac.

Examples:
    python3 simulate_states.py --cycle              # loop through all states
    python3 simulate_states.py --state editing      # set one state and exit
    python3 simulate_states.py --cycle --delay 2
"""
from __future__ import annotations

import argparse
import json
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from khosrow_pet import core  # noqa: E402


def set_state(state: str, print_only: bool, http: bool) -> dict:
    payload = core.build_payload(state, None, None)
    if not print_only:
        core.emit(payload, http_port=51763 if http else None)
    return payload


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--state", choices=core.STATES, help="set a single state")
    ap.add_argument("--cycle", action="store_true", help="cycle through all states")
    ap.add_argument("--delay", type=float, default=1.5, help="seconds per state")
    ap.add_argument("--loops", type=int, default=1, help="cycle repetitions (0 = forever)")
    ap.add_argument("--print-only", action="store_true")
    ap.add_argument("--no-http", action="store_true")
    args = ap.parse_args()
    http = not args.no_http

    if args.state:
        print(json.dumps(set_state(args.state, args.print_only, http)))
        return 0

    if args.cycle:
        count = 0
        while args.loops == 0 or count < args.loops:
            for state in core.STATES:
                payload = set_state(state, args.print_only, http)
                print(json.dumps(payload))
                time.sleep(args.delay)
            count += 1
        return 0

    ap.print_help()
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
