output "restart_ecs_task_arn" {
  value       = aws_ssm_document.restart_ecs_task.arn
  description = "ARN of the restart_ecs_task SSM Automation document."
}

output "restart_ec2_instance_arn" {
  value       = aws_ssm_document.restart_ec2_instance.arn
  description = "ARN of the restart_ec2_instance SSM Automation document."
}

output "scale_out_asg_arn" {
  value       = aws_ssm_document.scale_out_asg.arn
  description = "ARN of the scale_out_asg SSM Automation document."
}

output "rotate_rds_password_arn" {
  value       = aws_ssm_document.rotate_rds_password.arn
  description = "ARN of the rotate_rds_password SSM Automation document."
}

output "increase_ecs_memory_arn" {
  value       = aws_ssm_document.increase_ecs_memory.arn
  description = "ARN of the increase_ecs_memory SSM Automation document."
}

output "document_names" {
  value = {
    restart_ecs_task     = aws_ssm_document.restart_ecs_task.name
    restart_ec2_instance = aws_ssm_document.restart_ec2_instance.name
    scale_out_asg        = aws_ssm_document.scale_out_asg.name
    rotate_rds_password  = aws_ssm_document.rotate_rds_password.name
    increase_ecs_memory  = aws_ssm_document.increase_ecs_memory.name
  }
  description = "Map of runbook ID to SSM document name."
}
