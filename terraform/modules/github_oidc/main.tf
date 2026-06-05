# ── OIDC identity provider for GitHub Actions ─────────────────────────────
# This tells AWS to trust JWT tokens issued by token.actions.githubusercontent.com.
# AWS validates these tokens via its own libraries — the thumbprint is required
# by the API but is no longer used for validation (kept for historical compat).
resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

# ── Deploy role that the GitHub Actions runner assumes via OIDC ──────────
# Trust policy is locked down so ONLY this specific repo, running a job that
# targets the named GitHub Actions environment, can assume the role. No other
# repo, branch, or workflow can use it — even within the same AWS account.
data "aws_iam_policy_document" "trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_org}/${var.github_repo}:environment:${var.environment}"]
    }
  }
}

resource "aws_iam_role" "github_actions_deploy" {
  name               = "github-actions-deploy-${var.environment}"
  description        = "Assumed by GitHub Actions via OIDC to run terraform apply for the ${var.environment} environment."
  assume_role_policy = data.aws_iam_policy_document.trust.json
}

# ── Permissions ───────────────────────────────────────────────────────────
# AdministratorAccess is used here because terraform apply creates a wide
# variety of resources (Lambda, IAM, Step Functions, SSM, SES, API Gateway,
# DynamoDB, S3 backend, Secrets Manager) — enumerating each action would be
# fragile and easy to get wrong. The real security boundary is the OIDC
# trust policy above: this role can only be assumed by Achinthya18/SelfHeal
# on the "dev" environment, which itself requires manual reviewer approval.
# In a production setup you would narrow this to a custom least-privilege
# policy enumerated against the actual resource types deployed.
resource "aws_iam_role_policy_attachment" "github_actions_admin" {
  role       = aws_iam_role.github_actions_deploy.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}
