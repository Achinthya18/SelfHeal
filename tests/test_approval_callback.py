"""
tests/test_approval_callback.py

Unit tests for ApprovalCallbackLambda (handler.py, token_validator.py).
Run with: python -m pytest tests/test_approval_callback.py -v
"""

import hashlib
import hmac
import importlib.util
import os
import sys
import time
import unittest
from pathlib import Path
from unittest.mock import MagicMock, patch

# ── Set required env vars before importing Lambda modules ───────────────────
os.environ.setdefault("APPROVAL_TOKEN_SECRET", "test-secret-32-chars-padding-here")
os.environ.setdefault("DYNAMO_TABLE_NAME", "self-healing-incidents")

# ── Load approval_callback modules by explicit path (avoids sys.path clash) ─
CALLBACK_DIR = Path(__file__).parent.parent / "lambdas" / "approval_callback"


def _load(module_name: str):
    spec = importlib.util.spec_from_file_location(
        f"approval_callback.{module_name}",
        CALLBACK_DIR / f"{module_name}.py",
        submodule_search_locations=[str(CALLBACK_DIR)],
    )
    mod = importlib.util.module_from_spec(spec)
    sys.modules[f"approval_callback.{module_name}"] = mod
    # Also register bare name so intra-package imports work
    sys.modules[module_name] = mod
    spec.loader.exec_module(mod)
    return mod


token_validator = _load("token_validator")
dynamo_client = _load("dynamo_client")
cb_handler = _load("handler")

TokenExpiredError = token_validator.TokenExpiredError
TokenInvalidError = token_validator.TokenInvalidError
validate_token = token_validator.validate_token

# ── Helper: generate a valid HMAC token ────────────────────────────────────
SECRET = os.environ["APPROVAL_TOKEN_SECRET"]


def _make_token(incident_id: str, offset_seconds: int = 900) -> str:
    expiry = int(time.time()) + offset_seconds
    msg = f"{incident_id}:{expiry}".encode()
    mac = hmac.new(SECRET.encode(), msg, hashlib.sha256).hexdigest()
    return f"{expiry}.{mac}"


class TestTokenValidator(unittest.TestCase):

    def test_valid_token_passes(self):
        token = _make_token("inc-001", offset_seconds=900)
        validate_token(token, "inc-001")  # should not raise

    def test_expired_token_raises(self):
        token = _make_token("inc-001", offset_seconds=-60)
        with self.assertRaises(TokenExpiredError):
            validate_token(token, "inc-001")

    def test_wrong_incident_id_raises(self):
        token = _make_token("inc-001", offset_seconds=900)
        with self.assertRaises(TokenInvalidError):
            validate_token(token, "inc-999")

    def test_tampered_hmac_raises(self):
        token = _make_token("inc-001", offset_seconds=900)
        parts = token.split(".", 1)
        tampered = f"{parts[0]}.{'a' * 64}"
        with self.assertRaises(TokenInvalidError):
            validate_token(tampered, "inc-001")

    def test_malformed_token_raises(self):
        with self.assertRaises(TokenInvalidError):
            validate_token("not-a-valid-token", "inc-001")

    def test_non_integer_expiry_raises(self):
        with self.assertRaises(TokenInvalidError):
            validate_token("abc.deadbeef", "inc-001")


class TestApprovalHandler(unittest.TestCase):

    def _make_event(self, path: str = "/approve", extra_params: dict | None = None) -> dict:
        incident_id = "test-incident-id"
        token = _make_token(incident_id, offset_seconds=900)
        params = {
            "incident_id": incident_id,
            "created_at": "2026-05-27T00:00:00+00:00",
            "token": token,
            "task_token": "fake-step-functions-task-token",
        }
        if extra_params:
            params.update(extra_params)
        return {
            "path": path,
            "queryStringParameters": params,
            "httpMethod": "POST",
        }

    def _mock_incident(self, status="pending"):
        return {
            "incident_id": "test-incident-id",
            "created_at": "2026-05-27T00:00:00+00:00",
            "status": status,
            "recommended_runbook": "restart_ecs_task",
            "resource_arn": "arn:aws:ecs:ap-south-1:123:service/c/s",
        }

    def test_approve_returns_200(self):
        mock_sf = MagicMock()
        with patch.object(cb_handler, "get_incident", return_value=self._mock_incident()), \
             patch.object(cb_handler, "update_incident_status"), \
             patch.object(cb_handler, "_get_sf", return_value=mock_sf):
            result = cb_handler.handler(self._make_event("/approve"), None)

        self.assertEqual(result["statusCode"], 200)
        self.assertIn("Approved", result["body"])
        mock_sf.send_task_success.assert_called_once()

    def test_reject_returns_200(self):
        mock_sf = MagicMock()
        with patch.object(cb_handler, "get_incident", return_value=self._mock_incident()), \
             patch.object(cb_handler, "update_incident_status"), \
             patch.object(cb_handler, "_get_sf", return_value=mock_sf):
            result = cb_handler.handler(self._make_event("/reject"), None)

        self.assertEqual(result["statusCode"], 200)
        self.assertIn("Rejected", result["body"])
        mock_sf.send_task_failure.assert_called_once()

    def test_expired_token_returns_410(self):
        expired_token = _make_token("test-incident-id", offset_seconds=-60)
        event = self._make_event("/approve", extra_params={"token": expired_token})
        result = cb_handler.handler(event, None)
        self.assertEqual(result["statusCode"], 410)
        self.assertIn("Expired", result["body"])

    def test_missing_params_returns_400(self):
        event = {
            "path": "/approve",
            "queryStringParameters": {"incident_id": "abc"},  # missing token etc.
            "httpMethod": "POST",
        }
        result = cb_handler.handler(event, None)
        self.assertEqual(result["statusCode"], 400)

    def test_already_processed_returns_409(self):
        with patch.object(cb_handler, "get_incident", return_value=self._mock_incident("resolved")):
            result = cb_handler.handler(self._make_event("/approve"), None)
        self.assertEqual(result["statusCode"], 409)


if __name__ == "__main__":
    unittest.main()
