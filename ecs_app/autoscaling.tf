resource "aws_appautoscaling_policy" "ecs_scale_out_policy" {
  count = var.autoscaling_enable ? 1 : 0

  name               = "${var.service_name}-scale-out-policy"
  policy_type        = "StepScaling"
  resource_id        = "service/${var.ecs_cluster}/${var.service_name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"

  step_scaling_policy_configuration {
    adjustment_type         = "ChangeInCapacity"
    cooldown                = var.scale_out_cooldown
    metric_aggregation_type = "Average"

    step_adjustment {
      metric_interval_lower_bound = 0
      scaling_adjustment          = 1
    }
  }
}

resource "aws_appautoscaling_policy" "ecs_scale_in_policy" {
  count = var.autoscaling_enable ? 1 : 0

  name               = "${var.service_name}-scale-in-policy"
  policy_type        = "StepScaling"
  resource_id        = "service/${var.ecs_cluster}/${var.service_name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"

  step_scaling_policy_configuration {
    adjustment_type         = "ChangeInCapacity"
    cooldown                = var.scale_in_cooldown
    metric_aggregation_type = "Average"

    step_adjustment {
      metric_interval_upper_bound = 0
      scaling_adjustment          = -1
    }
  }
}

resource "aws_appautoscaling_target" "ecs_target" {
  count = var.autoscaling_enable ? 1 : 0

  service_namespace  = "ecs"
  resource_id        = "service/${var.ecs_cluster}/${var.service_name}"
  scalable_dimension = "ecs:service:DesiredCount"
  min_capacity       = var.min_capacity
  max_capacity       = var.max_capacity
}