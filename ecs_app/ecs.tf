resource "aws_ecs_service" "service" {
  name            = var.service_name
  cluster         = "${var.ecs_cluster}"
  task_definition = "${var.task_definition.arn}"
  launch_type     = var.launch_type
  desired_count   = var.desired_count

  dynamic "load_balancer" {
    for_each = var.create_lb ? [1] : []
    content {
      target_group_arn = aws_lb_target_group.alb[0].arn
      container_name   = var.task_definition.family
      container_port   = var.service_port
    }
  }

  network_configuration {
    subnets          = var.service_subnets
    assign_public_ip = var.assign_public_ip
    security_groups  = [aws_security_group.this.id]
  }

  # Conditional service registry block based on service_discovery variable
  dynamic "service_registries" {
    for_each = var.service_discovery ? [1] : []
    content {
      registry_arn = aws_service_discovery_service.service_discovery[0].arn
    }
  }

  lifecycle {
    ignore_changes = [task_definition]
  }

  enable_execute_command = true
  tags                   = var.tags
}

resource "aws_security_group" "this" {
  name        = "ecs-${var.service_name}-${var.env}-${var.instance}"
  description = "For ${var.service_name}"
  vpc_id      = var.vpc_id

  dynamic "ingress" {
    for_each = var.ingress_sg_ecs_rules
    iterator = rule
    content {
      from_port       = rule.value.from_port
      to_port         = rule.value.to_port
      protocol        = rule.value.protocol
      cidr_blocks     = rule.value.cidr_blocks
      description     = rule.value.description
    }
  }

  dynamic "egress" {
    for_each = var.egress_sg_ecs_rules
    iterator = rule
    content {
      from_port   = rule.value.from_port
      to_port     = rule.value.to_port
      protocol    = rule.value.protocol
      cidr_blocks = rule.value.cidr_blocks
      description = rule.value.description
    }
  }

  lifecycle { create_before_destroy = true }
}

resource "aws_service_discovery_private_dns_namespace" "private_dns_namespace" {
  count       = var.service_discovery ? 1 : 0
  name        = "${var.service_name}.local"
  description = "Private DNS namespace for ${var.service_name}"
  vpc         = var.vpc_id
}

resource "aws_service_discovery_service" "service_discovery" {
  count = var.service_discovery ? 1 : 0
  name  = var.service_name

  dns_config {
    namespace_id   = aws_service_discovery_private_dns_namespace.private_dns_namespace[0].id

    dns_records {
      ttl  = 10
      type = "A"
    }
  }
}

