locals {
  replayschemaregistry_port              = 8081
  replayschemaregistry_public_port       = 80
  replayschemaregistry_image             = "35452624567.dkr.ecr.${var.aws_region}.amazonaws.com/${var.project}/${local.replayschemaregistry_name}:${var.replayschemaregistry_tag}"
  replayschemaregistry_name              = "replay-schema-registry"
  replayschemaregistry_short_name        = "rsr"
  bootstrap_brokers_with_protocol        = join(",", [for broker in split(",", module.msk.msk_cluster.bootstrap_brokers): "PLAINTEXT://${broker}"])

  replayschemaregistry_ingress_lb_rules = [
    {
      cidr_blocks = [lookup(module.cidr.cidr_blocks[var.instance][var.project], var.env)]
      from_port   = 80
      to_port     = 80
      protocol    = "tcp"
      description = "HTTP Access from VPC"
    },
    {
      cidr_blocks = [lookup(module.cidr.cidr_blocks[var.instance][var.project], var.env)]
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      description = "HTTPs Access from VPC"
    },
    {
      cidr_blocks = var.ingress_allowed_cidrs
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      description = "HTTPS Access from public IP whitelist"
    },
    {
      cidr_blocks = var.ingress_allowed_cidrs
      from_port   = 8081
      to_port     = 8081
      protocol    = "tcp"
      description = "HTTPS Access from public IP whitelist"
    },
    {
      cidr_blocks = var.ingress_allowed_cidrs
      from_port   = 80
      to_port     = 80
      protocol    = "tcp"
      description = "HTTPS Access from public IP whitelist"
    },
  ]

  replayschemaregistry_egress_lb_rules = [
    {
      cidr_blocks = ["0.0.0.0/0"]
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
      description = "Allow all egress traffic"
    }
  ]

  replayschemaregistry_ingress_ecs_rules = [
    {
      cidr_blocks = [lookup(module.cidr.cidr_blocks[var.instance][var.project], var.env)]
      from_port   = 8081
      to_port     = 8081
      protocol    = "tcp"
      description = "Access from load balancer"
    },
    {
      cidr_blocks = [lookup(module.cidr.cidr_blocks[var.instance][var.project], var.env)]
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      description = "SSH access from bastion"
    },
    {
      cidr_blocks = [lookup(module.cidr.cidr_blocks[var.instance][var.project], var.env)]
      from_port   = 80
      to_port     = 80
      protocol    = "tcp"
      description = "Access from load balancer"
    }
  ]

  replayschemaregistry_egress_ecs_rules = [
    {
      cidr_blocks = ["0.0.0.0/0"]
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
      description = "Allow all egress traffic"
    }
  ]

  replayschemaregistry_tags = {service = "RSR", jira = "GDMP-1431"}
}

resource "aws_ecs_task_definition" "rsr_app_task" {
  family                   = local.replayschemaregistry_name
  container_definitions    = <<DEFINITION
  [
    {
      "name": "${local.replayschemaregistry_name}",
      "image": "${local.replayschemaregistry_image}",
      "essential": true,
      "portMappings": [
        {
          "containerPort": ${local.replayschemaregistry_port},
          "hostPort": ${local.replayschemaregistry_port}
        }
      ],
      "memory": 512,
      "cpu": 256,
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "${aws_cloudwatch_log_group.rsr_service.name}",
          "awslogs-region": "${var.aws_region}",
          "awslogs-stream-prefix": "${var.env_alias[var.env]}-${local.replayschemaregistry_name}"
        }
    },
      "environment": [
        {"name": "SCHEMA_REGISTRY_KAFKASTORE_BOOTSTRAP_SERVERS", "value": "${local.bootstrap_brokers_with_protocol}"},
        {"name": "SCHEMA_REGISTRY_HOST_NAME", "value": "https://replay-schema-registry.dev..."},
        {"name": "SCHEMA_REGISTRY_LISTENERS", "value": "http://0.0.0.0:${local.replayschemaregistry_port}"}
      ]

    }
  ]
  DEFINITION
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  memory                   = 512
  cpu                      = 256
  execution_role_arn       = "${aws_iam_role.ecsTaskExecutionRole.arn}"
  task_role_arn            = "${aws_iam_role.ecsTaskExecutionRole.arn}"
  tags                     = local.replayschemaregistry_tags
}

resource "aws_cloudwatch_log_group" "rsr_service" {
  name = "${var.project}/${var.instance}/${var.env_alias[var.env]}/ecs/${local.replayschemaregistry_name}"
  retention_in_days = var.ecs_log_retention
}

module "replayschemaregistry_service" {
  source = "./ecs_app"

  project                   = var.project
  instance                  = var.instance
  env                       = var.env
  service_port              = local.replayschemaregistry_port
  service_public_port       = local.replayschemaregistry_public_port
  service_name              = local.replayschemaregistry_name
  ecs_cluster               = aws_ecs_cluster.this.id
  task_definition           = aws_ecs_task_definition.rsr_app_task
  tags                      = local.replayschemaregistry_tags
  vpc_id                    = module.vpc.vpc.id
  service_subnets           = [module.tgw_subnets.subnets[0].id, module.tgw_subnets.subnets[1].id]
  ingress_sg_ecs_rules      = local.replayschemaregistry_ingress_ecs_rules
  egress_sg_ecs_rules       = local.replayschemaregistry_egress_ecs_rules
  alb_subnet_ids            = module.lb_subnets.subnets.*.id
  ingress_sg_rules          = local.replayschemaregistry_ingress_lb_rules
  egress_sg_rules           = local.replayschemaregistry_egress_lb_rules
  logging_s3_bucket         = aws_s3_bucket.alb-access-logs
  dns_zone_id               = aws_route53_zone.delegated.zone_id
  acm_certificate           = aws_acm_certificate.shared_public_lb
  service_discovery         = true
  email_subscribers         = var.replay_email_subscribers
  high_cpu_threshold        = 90
  high_memory_threshold     = 90

  health_check = {
    enabled             = true
    healthy_threshold   = 2
    interval            = 30
    path                = "/subjects"
    matcher             = "200"
    port                = local.replayschemaregistry_port
    protocol            = "HTTP"
    timeout             = 5
    unhealthy_threshold = 2
  }
}


