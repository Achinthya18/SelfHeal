output "dashboard_name" {
  value       = aws_cloudwatch_dashboard.self_healing.dashboard_name
  description = "Name of the CloudWatch dashboard."
}

output "dashboard_url" {
  value       = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${aws_cloudwatch_dashboard.self_healing.dashboard_name}"
  description = "Direct console link to the dashboard."
}
