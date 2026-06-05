output "deploy_role_arn" {
  value       = aws_iam_role.github_actions_deploy.arn
  description = "ARN of the role GitHub Actions assumes via OIDC. Set this as AWS_DEPLOY_ROLE_ARN in the GitHub Actions environment."
}

output "oidc_provider_arn" {
  value       = aws_iam_openid_connect_provider.github.arn
  description = "ARN of the GitHub OIDC identity provider."
}
