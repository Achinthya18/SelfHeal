output "state_machine_arn" {
  value       = aws_sfn_state_machine.self_healing.arn
  description = "ARN of the self-healing Step Functions state machine."
}

output "state_machine_name" {
  value       = aws_sfn_state_machine.self_healing.name
  description = "Name of the self-healing Step Functions state machine."
}
