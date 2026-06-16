# CloudWatch Log Groups

resource "aws_cloudwatch_log_group" "app" {
  for_each = local.servicios_infra

  name              = "/casino/${each.key}"
  retention_in_days = var.log_retention_days

  tags = merge(local.tags, { Name = "lg-${each.key}-${local.name_suffix}" })
}

resource "aws_cloudwatch_log_group" "ec2_system" {
  name              = "/casino/system"
  retention_in_days = var.log_retention_days

  tags = merge(local.tags, { Name = "lg-system-${local.name_suffix}" })
}

resource "aws_cloudwatch_log_group" "alb" {
  name              = "/casino/alb"
  retention_in_days = var.log_retention_days

  tags = merge(local.tags, { Name = "lg-alb-${local.name_suffix}" })
}

# SNS

resource "aws_sns_topic" "alerts" {
  name = "alerts-${local.name_suffix}"

  tags = merge(local.tags, { Name = "alerts-${local.name_suffix}" })
}

resource "aws_sns_topic_subscription" "alerts_email" {
  for_each = toset(var.alarm_email != "" ? [var.alarm_email] : [])

  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = each.value
}

# Alarmas

resource "aws_cloudwatch_metric_alarm" "alb_5xx" {
  alarm_name          = "alarm-alb-5xx-${local.name_suffix}"
  alarm_description   = "Mas de 10 errores 5xx en el ALB en 5 minutos"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "HTTPCode_ELB_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 300
  statistic           = "Sum"
  threshold           = 10
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]

  dimensions = {
    LoadBalancer = aws_lb.main.arn_suffix
  }

  tags = merge(local.tags, { Name = "alarm-5xx-${local.name_suffix}" })
}

resource "aws_cloudwatch_metric_alarm" "alb_latency" {
  alarm_name          = "alarm-alb-latency-${local.name_suffix}"
  alarm_description   = "Latencia promedio del ALB supera 2 segundos"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "TargetResponseTime"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Average"
  threshold           = 2
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]

  dimensions = {
    LoadBalancer = aws_lb.main.arn_suffix
  }

  tags = merge(local.tags, { Name = "alarm-latency-${local.name_suffix}" })
}
