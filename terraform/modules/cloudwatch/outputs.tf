output "manual_test_alarm_name" {
  value       = aws_cloudwatch_metric_alarm.manual_test.alarm_name
  description = "Name of the manually-triggerable test alarm."
}

output "demo_log_group_name" {
  value       = aws_cloudwatch_log_group.demo_service.name
  description = "Name of the demo log group used during testing."
}
