# Self-Healing Infrastructure with AI Runbooks

Automatically detects AWS infrastructure failures, uses Gemini 2.5 Flash to diagnose the issue from CloudWatch logs, sends a human-in-the-loop approval email via SES, and executes the fix using SSM Automation upon approval — all orchestrated by AWS Step Functions.

See [PROJECT.md](PROJECT.md) for full architecture, workflow, and design decisions.
