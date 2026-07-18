"""Khosrow pet bridge — maps Claude Code hook events to minimal pet states.

Privacy contract: this package only ever emits {state, toolCategory, timestamp,
success}. It never reads or forwards prompt text, source code, file contents,
command strings, credentials, or secrets. See ``core.redact``.
"""

__all__ = ["core", "settings_merge"]
