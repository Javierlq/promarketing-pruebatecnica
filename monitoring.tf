###############################################################################
# monitoring.tf
# Observabilidad: CloudWatch Log Groups centralizados para EC2 y aplicaciones,
# y alarmas para errores 5xx y alta latencia en el ALB.
# Los access logs del ALB se configuran en instances.tf (resource aws_lb).

# =============================================================================
# LOG GROUPS DE CLOUDWATCH

resource "aws_cloudwatch_log_group" "app" {
  for_each = toset(var.apps)

  name              = "/casino/${each.key}"
  retention_in_days = var.log_retention_days

  tags = merge(local.tags, { Name = "lg-${each.key}-${local.name_suffix}" })
}

# Log group para el sistema (logs del OS / agente en las EC2)
resource "aws_cloudwatch_log_group" "ec2_system" {
  name              = "/casino/system"
  retention_in_days = var.log_retention_days

  tags = merge(local.tags, { Name = "lg-system-${local.name_suffix}" })
}

# Log group para el ALB (complementa los access logs en S3)
resource "aws_cloudwatch_log_group" "alb" {
  name              = "/casino/alb"
  retention_in_days = var.log_retention_days

  tags = merge(local.tags, { Name = "lg-alb-${local.name_suffix}" })
}

# =============================================================================
# ALARMA: errores HTTP 5xx en el ALB
# Se dispara cuando el ALB responde con mas de 10 errores 5xx en 5 minutos.

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

  dimensions = {
    LoadBalancer = aws_lb.main.arn_suffix
  }

  tags = merge(local.tags, { Name = "alarm-5xx-${local.name_suffix}" })
}

# =============================================================================
# ALARMA: alta latencia en el ALB
# Se dispara cuando el tiempo de respuesta promedio supera los 2 segundos.

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

  dimensions = {
    LoadBalancer = aws_lb.main.arn_suffix
  }

  tags = merge(local.tags, { Name = "alarm-latency-${local.name_suffix}" })
}
