"""Anonymous ownership for users' own profiles and runs.

The browser generates a random key (256 bits, base64url) and sends it as `X-Profile-Key`.
The server only ever stores and compares its SHA-256, so a database row can't be used to
find or impersonate a user. Requests never log headers.
"""
from __future__ import annotations

import hashlib
import re

from fastapi import Request

from app.errors import ApiError

HEADER = "x-profile-key"
_KEY = re.compile(r"^[A-Za-z0-9_-]{32,128}$")


def owner_from(request: Request, required: bool = False) -> str | None:
    """SHA-256 hex of the caller's profile key, or None when absent and not required."""
    key = request.headers.get(HEADER)
    if not key:
        if required:
            raise ApiError(401, "PROFILE_KEY_REQUIRED", "Save your numbers first; this needs your profile key.")
        return None
    if not _KEY.match(key):
        raise ApiError(422, "INVALID_REQUEST", "The profile key is not valid.", [HEADER])
    return hashlib.sha256(key.encode("ascii")).hexdigest()
