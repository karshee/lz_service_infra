output "ecs_service" {
  value = aws_ecs_service.service
}

output "load_balancer" {
    value = module.service_lb
}

output "target_group" {
  value = aws_lb_target_group.alb
}

output "security_group" {
  value = aws_security_group.this
}
