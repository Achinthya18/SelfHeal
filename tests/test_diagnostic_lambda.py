"""
tests/test_diagnostic_lambda.py

Unit tests for DiagnosticLambda (handler.py, gemini_client.py, cloudwatch_client.py).
Run with: python -m pytest tests/test_diagnostic_lambda.py -v
"""

import importlib.util
import sys
import unittest
from pathlib import Path
from unittest.mock import MagicMock, patch

# ── Load diagnostic modules by explicit path (avoids sys.path clash) ────────
DIAG_DIR = Path(__file__).parent.parent / "lambdas" / "diagnostic"


def _load(module_name: str):
    spec = importlib.util.spec_from_file_location(
        f"diagnostic.{module_name}",
        DIAG_DIR / f"{module_name}.py",
        submodule_search_locations=[str(DIAG_DIR)],
    )
    mod = importlib.util.module_from_spec(spec)
    sys.modules[f"diagnostic.{module_name}"] = mod
    sys.modules[module_name] = mod
    spec.loader.exec_module(mod)
    return mod


cloudwatch_client = _load("cloudwatch_client")
gemini_client = _load("gemini_client")
diag_handler = _load("handler")


class TestCloudWatchClient(unittest.TestCase):
    """Tests for cloudwatch_client.get_recent_logs"""

    def setUp(self):
        # Reset module-level client cache between tests
        cloudwatch_client._logs_client = None

    @patch("cloudwatch_client.boto3")
    def test_returns_log_messages(self, mock_boto3):
        mock_client = MagicMock()
        mock_boto3.client.return_value = mock_client

        mock_paginator = MagicMock()
        mock_client.get_paginator.return_value = mock_paginator
        mock_paginator.paginate.return_value = [
            {
                "events": [
                    {"message": "ERROR: connection refused\n"},
                    {"message": "WARN: retry attempt 3\n"},
                ]
            }
        ]

        result = cloudwatch_client.get_recent_logs("/ecs/my-service", minutes=30, limit=100)
        self.assertEqual(result, ["ERROR: connection refused", "WARN: retry attempt 3"])

    def test_format_logs_for_prompt_empty(self):
        result = cloudwatch_client.format_logs_for_prompt([])
        self.assertIn("no log events", result)

    def test_format_logs_for_prompt_numbers_lines(self):
        result = cloudwatch_client.format_logs_for_prompt(["line A", "line B"])
        self.assertIn("1:", result)
        self.assertIn("2:", result)
        self.assertIn("line A", result)


class TestGeminiClientValidation(unittest.TestCase):
    """Tests for _validate_response in gemini_client"""

    def test_valid_response_passes(self):
        valid = {
            "diagnosis": "The ECS task is crash-looping due to OOM.",
            "recommended_runbook": "restart_ecs_task",
            "confidence": "high",
            "reasoning": "OOM kill visible in logs.",
        }
        gemini_client._validate_response(valid)  # should not raise

    def test_missing_key_raises(self):
        incomplete = {
            "diagnosis": "...",
            "recommended_runbook": "restart_ecs_task",
            "confidence": "high",
            # "reasoning" missing
        }
        with self.assertRaises(ValueError) as ctx:
            gemini_client._validate_response(incomplete)
        self.assertIn("reasoning", str(ctx.exception))

    def test_invalid_runbook_raises(self):
        bad = {
            "diagnosis": "...",
            "recommended_runbook": "destroy_all_instances",
            "confidence": "high",
            "reasoning": "...",
        }
        with self.assertRaises(ValueError) as ctx:
            gemini_client._validate_response(bad)
        self.assertIn("destroy_all_instances", str(ctx.exception))

    def test_invalid_confidence_raises(self):
        bad = {
            "diagnosis": "...",
            "recommended_runbook": "restart_ecs_task",
            "confidence": "very_high",
            "reasoning": "...",
        }
        with self.assertRaises(ValueError):
            gemini_client._validate_response(bad)

    def test_confidence_normalised_to_lowercase(self):
        item = {
            "diagnosis": "...",
            "recommended_runbook": "scale_out_asg",
            "confidence": "HIGH",
            "reasoning": "...",
        }
        gemini_client._validate_response(item)
        self.assertEqual(item["confidence"], "high")


class TestDiagnosticHandler(unittest.TestCase):
    """Tests for diag_handler.handler"""

    def _make_event(self):
        return {
            "alarm_name": "ecs-health-check-failed",
            "alarm_arn": "arn:aws:cloudwatch:ap-south-1:123:alarm:test",
            "resource_arn": "arn:aws:ecs:ap-south-1:123:service/cluster/svc",
            "log_group_name": "/ecs/my-service",
        }

    def _gemini_response(self):
        return {
            "diagnosis": "ECS task is crash-looping due to OOM.",
            "recommended_runbook": "restart_ecs_task",
            "confidence": "high",
            "reasoning": "OOM kills visible in container logs.",
        }

    def test_handler_returns_full_output(self):
        with patch.object(diag_handler, "get_recent_logs", return_value=["ERROR OOM kill"]), \
             patch.object(diag_handler, "invoke_gemini", return_value=self._gemini_response()):
            result = diag_handler.handler(self._make_event(), None)

        self.assertIn("incident_id", result)
        self.assertEqual(result["recommended_runbook"], "restart_ecs_task")
        self.assertEqual(result["confidence"], "high")
        self.assertIn("diagnosis", result)
        self.assertIn("logs_snapshot", result)

    def test_handler_generates_unique_incident_ids(self):
        with patch.object(diag_handler, "get_recent_logs", return_value=[]), \
             patch.object(diag_handler, "invoke_gemini", return_value=self._gemini_response()):
            r1 = diag_handler.handler(self._make_event(), None)
            r2 = diag_handler.handler(self._make_event(), None)
        self.assertNotEqual(r1["incident_id"], r2["incident_id"])

    def test_handler_proceeds_without_logs(self):
        """DiagnosticLambda should continue even when log fetch raises."""
        with patch.object(diag_handler, "get_recent_logs", side_effect=Exception("CW unavailable")), \
             patch.object(diag_handler, "invoke_gemini", return_value=self._gemini_response()):
            result = diag_handler.handler(self._make_event(), None)
        self.assertIn("incident_id", result)

    def test_handler_no_log_group_skips_fetch(self):
        with patch.object(diag_handler, "get_recent_logs") as mock_logs, \
             patch.object(diag_handler, "invoke_gemini", return_value=self._gemini_response()):
            event = self._make_event()
            event["log_group_name"] = ""
            result = diag_handler.handler(event, None)

        mock_logs.assert_not_called()
        self.assertIn("incident_id", result)


if __name__ == "__main__":
    unittest.main()
