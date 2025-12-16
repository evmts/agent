"""ID generation utility."""

import secrets


def gen_id(prefix: str) -> str:
    """Generate IDs matching OpenCode format: ses_xxx, msg_xxx, prt_xxx"""
    return f"{prefix}{secrets.token_urlsafe(12)}"
