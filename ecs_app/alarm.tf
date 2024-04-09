resource "aws_sns_topic" "alarm_sns_topic" {
  name = "${var.env}-${var.service_name}-alarms"
}

resource "aws_cloudwatch_metric_alarm" "high_cpu_utilization" {
  alarm_name          = "${var.service_name}-high-cpu-utilization-${var.instance}-XXXX-${var.env}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = "60"
  statistic           = "Average"
  threshold           = var.high_cpu_threshold
  alarm_description   = "This metric triggers when CPU utilization exceeds the threshold over 2 periods (2 min)"
  alarm_actions       = var.autoscaling_enable ? [aws_appautoscaling_policy.ecs_scale_out_policy[0].arn, aws_sns_topic.alarm_sns_topic.arn] : [aws_sns_topic.alarm_sns_topic.arn]

  dimensions = {
    ClusterName = "${var.project}-${var.env}-${var.instance}"
    ServiceName = var.service_name
  }

  treat_missing_data = "notBreaching"
}

resource "aws_cloudwatch_metric_alarm" "high_memory_utilization" {
  alarm_name          = "${var.service_name}-high-memory-utilization"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "MemoryUtilization"
  namespace           = "AWS/ECS"
  period              = "60"
  statistic           = "Average"
  threshold           = var.high_memory_threshold
  alarm_description   = "This metric triggers when memory utilization exceeds 80% over 2 periods (2 min)"
  alarm_actions       = var.autoscaling_enable ? [aws_appautoscaling_policy.ecs_scale_out_policy[0].arn, aws_sns_topic.alarm_sns_topic.arn] : [aws_sns_topic.alarm_sns_topic.arn]

  dimensions = {
    ClusterName = "${var.project}-${var.env}-${var.instance}"
    ServiceName = var.service_name
  }

  treat_missing_data = "notBreaching"
}

resource "aws_cloudwatch_metric_alarm" "unhealthy_host_count" {
  alarm_name          = "${var.instance}-XXXXXX-${var.env}-${var.service_name}-unhealthy-host-count"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "2"
  metric_name         = "UnHealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = "60"
  statistic           = "Sum"
  threshold           = 1
  alarm_description   = "This metric triggers when there is at least 1 unhealthy host over 2 periods (2 min)"
  alarm_actions       = [aws_sns_topic.alarm_sns_topic.arn]

  dimensions = {
    ClusterName = "${var.project}-${var.env}-${var.instance}"
    ServiceName = var.service_name
  }

  treat_missing_data = "notBreaching"
}

resource "aws_cloudwatch_metric_alarm" "low_memory_utilization" {
  alarm_name          = "${var.service_name}-low-memory-utilization"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "5"
  metric_name         = "MemoryUtilization"
  namespace           = "AWS/ECS"
  period              = "60"
  statistic           = "Average"
  threshold           = "5"
  alarm_description   = "This metric triggers when memory utilization exceeds 80% over 2 periods (2 min)"
  alarm_actions       = var.autoscaling_enable ? [aws_appautoscaling_policy.ecs_scale_in_policy[0].arn, aws_sns_topic.alarm_sns_topic.arn] : [aws_sns_topic.alarm_sns_topic.arn]

  dimensions = {
    ClusterName = "${var.project}-${var.env}-${var.instance}"
    ServiceName = var.service_name
  }

  treat_missing_data = "notBreaching"
}

resource "aws_sns_topic_subscription" "sns_email_subscriptions" {
  for_each = { for email in var.email_subscribers : email => email }

  topic_arn         = aws_sns_topic.alarm_sns_topic.arn
  protocol          = "email"
  endpoint          = each.value
  confirmation_timeout_in_minutes = 1
}