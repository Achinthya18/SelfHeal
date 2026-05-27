"""
token_validator.py — validates the HMAC-signed approval token from the email URL.

Token format:  "<expiry_unix_ts>.<hmac_hex>"

The HMAC is computed as:
    HMAC-SHA256(key=APPROVAL_TOKEN_SECRET, msg=f"{incident_id}:{expiry_ts}")

Validation rules:
1. Token can be split on "." into exactly two parts.
2. expiry_ts must be a valid integer.
3. Current time must be <= expiry_ts  (not expired).
4. Recomputed HMAC must match the provided HMAC (constant-time comparison).
"""

import hashlib
import hmac
import logging
import os
import time

logger = logging.getLogger(__name__)
logger.setLevel(os.environ.get("LOG_LEVEL", "INFO"))

APPROVAL_TOKEN_SECRET = os.environ.get("APPROVAL_TOKEN_SECRET", "")


class TokenExpiredError(Exception):
    """Raised when the token is structurally valid but past its expiry time."""


class TokenInvalidError(Exception):
    """Raised when the token cannot be parsed or the HMAC does not match."""


def validate_token(token: str, incident_id: str) -> None:
    """
    Validate an approval token.

    Parameters
    ----------
    token : str
        The raw token string from the URL query parameter.
    incident_id : str
        The incident ID from the URL query parameter.

    Raises
    ------
    TokenExpiredError
        If the token is valid but has passed its expiry time.
    TokenInvalidError
        If the token is malformed or the HMAC does not match.
    """
    if not APPROVAL_TOKEN_SECRET:
        raise EnvironmentError("APPROVAL_TOKEN_SECRET environment variable is not set")

    # ── Parse ───────────────────────────────────────────────────────────────
    parts = token.split(".", 1)
    if len(parts) != 2:
        logger.warning("Token format invalid (expected <ts>.<hmac>): %s", token[:40])
        raise TokenInvalidError("Token format is invalid")

    expiry_str, provided_mac = parts

    try:
        expiry_ts = int(expiry_str)
    except ValueError:
        raise TokenInvalidError("Token expiry timestamp is not an integer")

    # ── Expiry check ────────────────────────────────────────────────────────
    now = int(time.time())
    if now > expiry_ts:
        logger.info(
            "Token expired for incident %s: expired at %s, now %s",
            incident_id, expiry_ts, now
        )
        raise TokenExpiredError(
            f"Approval link expired {now - expiry_ts} seconds ago"
        )

    # ── HMAC check ──────────────────────────────────────────────────────────
    message = f"{incident_id}:{expiry_ts}".encode()
    expected_mac = hmac.new(
        APPROVAL_TOKEN_SECRET.encode(), message, hashlib.sha256
    ).hexdigest()

    if not hmac.compare_digest(expected_mac, provided_mac):
        logger.warning("HMAC mismatch for incident %s", incident_id)
        raise TokenInvalidError("Token signature is invalid")

    logger.info("Token validated successfully for incident %s", incident_id)
