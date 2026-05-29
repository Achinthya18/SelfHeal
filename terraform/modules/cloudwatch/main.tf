# ── Demo log group ────────────────────────────────────────────────────────────
# DiagnosticLambda will query this group. It can be empty; the Lambda handles
# missing log events gracefully and Gemini diagnoses from the alarm context alone.
resource "aws_cloudwatch_log_group" "demo_service" {
  name              = "/self-healing/demo-service"
  retention_in_days = 7
}

# ── Alarm 1: ECS service health (HealthyHostCount < 1) ───────────────────────
# Monitors an Application Load Balancer target group. Stays in INSUFFICIENT_DATA
# until a real ALB target group exists; manually trigger with set-alarm-state.
resource "aws_cloudwatch_metric_alarm" "ecs_health" {
  alarm_name          = "self-healing-ecs-health-demo"
  alarm_description   = "ECS service has no healthy tasks behind the load balancer"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HealthyHostCount"
  statistic           = "Minimum"
  period              = 60
  evaluation_periods  = 2
  threshold           = 1
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = "app/self-healing-demo/placeholder"
    TargetGroup  = "targetgroup/self-healing-demo/placeholder"
  }

  tags = {
    Runbook = "restart_ecs_task"
  }
}

# ── Alarm 2: EC2 CPU utilisation > 90 % ──────────────────────────────────────
resource "aws_cloudwatch_metric_alarm" "ec2_cpu" {
  alarm_name          = "self-healing-ec2-cpu-demo"
  alarm_description   = "EC2 instance CPU utilisation is critically high"
  namespace           = "AWS/EC2"
  metric_name         = "CPUUtilization"
  statistic           = "Average"
  period              = 120
  evaluation_periods  = 2
  threshold           = 90
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  tags = {
    Runbook = "restart_ec2_instance"
  }
}

# ── Alarm 3: Manual test alarm ────────────────────────────────────────────────
# Uses a custom metric that is never published, so the alarm stays in
# INSUFFICIENT_DATA at rest. Trigger manually with:
#   aws cloudwatch set-alarm-state \
#     --alarm-name self-healing-manual-test \
#     --state-value ALARM \
#     --state-reason "manual end-to-end test" \
#     --region ap-south-1
resource "aws_cloudwatch_metric_alarm" "manual_test" {
  alarm_name          = "self-healing-manual-test"
  alarm_description   = "Manual trigger for end-to-end self-healing pipeline testing"
  namespace           = "SelfHealing/Test"
  metric_name         = "ManualTestMetric"
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"

  tags = {
    Runbook = "restart_ecs_task"
  }
}
