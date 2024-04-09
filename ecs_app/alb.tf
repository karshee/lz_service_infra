module "service_lb" {
  count = var.create_lb ? 1 : 0

  source = "../modules/alb"

  name                 = var.service_name
  env                  = var.env
  vpc_id               = var.vpc_id
  instance             = var.instance
  subnets_ids          = var.alb_subnet_ids
  listener_certificate = var.acm_certificate
  ingress_sg_rules     = var.ingress_sg_rules
  egress_sg_rules      = var.egress_sg_rules
  cloudflare_zone      = var.cloudflare_zone
  logging_s3_bucket    = var.logging_s3_bucket
  access_logging       = var.access_logging
  default_action       = var.default_action
  target_group_arn     = aws_lb_target_group.alb[0].arn

  dns = [
    { name = var.service_name, zone_id = var.dns_zone_id }
  ]

}

resource "aws_lb_target_group" "alb" {
  count = var.create_lb ? 1 : 0

  vpc_id               = var.vpc_id
  name                 = "${var.service_name}-${var.env}-${var.instance}"
  port                 = var.service_public_port != null ? var.service_public_port : var.service_port
  protocol             = "HTTP"
  target_type          = "ip"
  deregistration_delay = 30

  health_check {
    enabled             = var.health_check.enabled
    healthy_threshold   = var.health_check.healthy_threshold
    interval            = var.health_check.interval
    path                = var.health_check.path
    matcher             = var.health_check.matcher
    port                = var.health_check.port
    protocol            = var.health_check.protocol
    timeout             = var.health_check.timeout
    unhealthy_threshold = var.health_check.unhealthy_threshold
  }

  tags = var.tags
}
