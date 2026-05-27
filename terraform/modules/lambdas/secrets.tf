resource "aws_secretsmanager_secret" "gemini_api_key" {
  name                    = "self-healing/gemini-api-key"
  description             = "Gemini API key for DiagnosticLambda"
  recovery_window_in_days = 0
}

# Placeholder value — update after apply with:
# aws secretsmanager update-secret \
#   --secret-id self-healing/gemini-api-key \
#   --secret-string "YOUR_REAL_GEMINI_API_KEY" \
#   --region ap-south-1
resource "aws_secretsmanager_secret_version" "gemini_api_key" {
  secret_id     = aws_secretsmanager_secret.gemini_api_key.id
  secret_string = "PLACEHOLDER_REPLACE_WITH_REAL_KEY"
}
