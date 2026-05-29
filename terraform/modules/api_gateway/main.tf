# ── REST API ─────────────────────────────────────────────────────────────────
resource "aws_api_gateway_rest_api" "self_healing" {
  name        = "self-healing-approval-${var.environment}"
  description = "Approve/reject callbacks for the self-healing incident workflow"

  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

# ── /approve resource + method + integration ─────────────────────────────────
resource "aws_api_gateway_resource" "approve" {
  rest_api_id = aws_api_gateway_rest_api.self_healing.id
  parent_id   = aws_api_gateway_rest_api.self_healing.root_resource_id
  path_part   = "approve"
}

resource "aws_api_gateway_method" "approve" {
  rest_api_id   = aws_api_gateway_rest_api.self_healing.id
  resource_id   = aws_api_gateway_resource.approve.id
  http_method   = "ANY"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "approve" {
  rest_api_id             = aws_api_gateway_rest_api.self_healing.id
  resource_id             = aws_api_gateway_resource.approve.id
  http_method             = aws_api_gateway_method.approve.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = "arn:aws:apigateway:${var.aws_region}:lambda:path/2015-03-31/functions/${var.approval_callback_lambda_arn}/invocations"
}

# ── /reject resource + method + integration ──────────────────────────────────
resource "aws_api_gateway_resource" "reject" {
  rest_api_id = aws_api_gateway_rest_api.self_healing.id
  parent_id   = aws_api_gateway_rest_api.self_healing.root_resource_id
  path_part   = "reject"
}

resource "aws_api_gateway_method" "reject" {
  rest_api_id   = aws_api_gateway_rest_api.self_healing.id
  resource_id   = aws_api_gateway_resource.reject.id
  http_method   = "ANY"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "reject" {
  rest_api_id             = aws_api_gateway_rest_api.self_healing.id
  resource_id             = aws_api_gateway_resource.reject.id
  http_method             = aws_api_gateway_method.reject.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = "arn:aws:apigateway:${var.aws_region}:lambda:path/2015-03-31/functions/${var.approval_callback_lambda_arn}/invocations"
}

# ── Deployment + Stage ───────────────────────────────────────────────────────
resource "aws_api_gateway_deployment" "self_healing" {
  rest_api_id = aws_api_gateway_rest_api.self_healing.id

  # Redeploy whenever the API structure changes
  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.approve.id,
      aws_api_gateway_method.approve.id,
      aws_api_gateway_integration.approve.id,
      aws_api_gateway_resource.reject.id,
      aws_api_gateway_method.reject.id,
      aws_api_gateway_integration.reject.id,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [
    aws_api_gateway_integration.approve,
    aws_api_gateway_integration.reject,
  ]
}

resource "aws_api_gateway_stage" "v1" {
  deployment_id = aws_api_gateway_deployment.self_healing.id
  rest_api_id   = aws_api_gateway_rest_api.self_healing.id
  stage_name    = "v1"
}

# ── Lambda permission: allow API Gateway to invoke ApprovalCallbackLambda ────
resource "aws_lambda_permission" "api_gateway_approve" {
  statement_id  = "AllowAPIGatewayApprove"
  action        = "lambda:InvokeFunction"
  function_name = var.approval_callback_lambda_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.self_healing.execution_arn}/*/*"
}
