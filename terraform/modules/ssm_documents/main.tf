resource "aws_ssm_document" "restart_ecs_task" {
  name            = "self-healing-restart-ecs-task"
  document_type   = "Automation"
  document_format = "YAML"
  content         = file("${path.module}/../../../ssm-documents/restart_ecs_task.yaml")

  tags = {
    Runbook = "restart_ecs_task"
  }
}

resource "aws_ssm_document" "restart_ec2_instance" {
  name            = "self-healing-restart-ec2-instance"
  document_type   = "Automation"
  document_format = "YAML"
  content         = file("${path.module}/../../../ssm-documents/restart_ec2_instance.yaml")

  tags = {
    Runbook = "restart_ec2_instance"
  }
}

resource "aws_ssm_document" "scale_out_asg" {
  name            = "self-healing-scale-out-asg"
  document_type   = "Automation"
  document_format = "YAML"
  content         = file("${path.module}/../../../ssm-documents/scale_out_asg.yaml")

  tags = {
    Runbook = "scale_out_asg"
  }
}

resource "aws_ssm_document" "rotate_rds_password" {
  name            = "self-healing-rotate-rds-password"
  document_type   = "Automation"
  document_format = "YAML"
  content         = file("${path.module}/../../../ssm-documents/rotate_rds_password.yaml")

  tags = {
    Runbook = "rotate_rds_password"
  }
}

resource "aws_ssm_document" "increase_ecs_memory" {
  name            = "self-healing-increase-ecs-memory"
  document_type   = "Automation"
  document_format = "YAML"
  content         = file("${path.module}/../../../ssm-documents/increase_ecs_memory.yaml")

  tags = {
    Runbook = "increase_ecs_memory"
  }
}
