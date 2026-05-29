output "rule_name" {
  value       = aws_cloudwatch_event_rule.alarm_to_alarm.name
  description = "Name of the EventBridge rule that triggers the self-healing workflow."
}

output "rule_arn" {
  value       = aws_cloudwatch_event_rule.alarm_to_alarm.arn
  description = "ARN of the EventBridge rule."
}
