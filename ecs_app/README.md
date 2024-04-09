Example of declaring module :
```
module "betsettingsuploader_service" {
  source = "./ecs"

  project                   = var.project
  instance                  = var.instance
  env                       = var.env
  service_port              = local.betsettingsuploader_port
  service_name              = local.betsettings_service_name
  ecs_cluster               = aws_ecs_cluster.this.id
  task_definition           = aws_ecs_task_definition.app_task
  tags                      = local.tags
  vpc_id                    = module.vpc.vpc.id
  service_subnets           = [module.lb_subnets_internal.subnets[0].id, module.lb_subnets_internal.subnets[1].id]
  alb_subnet_ids            = module.lb_subnets.subnets.*.id
  ingress_sg_rules          = local.betsettingsuploader_ingress_extelb_rules
  egress_sg_rules           = local.betsettingsuploader_egress_extelb_rules
  logging_s3_bucket         = aws_s3_bucket.alb-access-logs
  dns_zone_id               = aws_route53_zone.delegated.zone_id

  health_check = {
    enabled             = true
    healthy_threshold   = 2
    interval            = 60
    path                = "/"
    matcher             = "200"
    port                = local.betsettingsuploader_port
    protocol            = "HTTP"
    timeout             = 5
    unhealthy_threshold = 2
  }
}
```