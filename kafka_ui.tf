locals {
  kafka_ui_port            = 8080
  kafka_ui_image           = "024059182542.dkr.ecr.${var.aws_region}.amazonaws.com/${var.project}/${local.kafka_ui_name}:latest"
  kafka_ui_name            = "kafka-ui"

  kafka_ui_ingress_lb_rules = [
    {
      cidr_blocks = [lookup(module.cidr.cidr_blocks[var.instance][var.project], var.env)]
      from_port   = 80
      to_port     = 80
      protocol    = "tcp"
      description = "HTTP Access from VPC"
    },
    {
      cidr_blocks = var.ingress_allowed_cidrs
      from_port   = 80
      to_port     = 80
      protocol    = "tcp"
      description = "HTTP Access from public IP whitelist"
    },
    {
      cidr_blocks = var.ingress_allowed_cidrs
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      description = "HTTPS Access from public IP whitelist"
    }
  ]

  kafka_ui_egress_lb_rules = [
    {
      cidr_blocks = ["0.0.0.0/0"]
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
      description = "Allow all egress traffic"
    }
  ]

  kafka_ui_ingress_ecs_rules = [
    {
      cidr_blocks = [lookup(module.cidr.cidr_blocks[var.instance][var.project], var.env)]
      from_port   = 8080
      to_port     = 8080
      protocol    = "tcp"
      description = "Access from load balancer"
    },
  ]

  kafka_ui_egress_ecs_rules = [
    {
      cidr_blocks = ["0.0.0.0/0"]
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
      description = "Allow all egress traffic"
    }
  ]
}

resource "aws_ecs_task_definition" "kafka_ui_task" {
  family                   = local.kafka_ui_name
  container_definitions    = <<DEFINITION
[
  {
    "name": "${local.kafka_ui_name}",
    "image": "${local.kafka_ui_image}",
    "essential": true,
    "portMappings": [
      {
        "containerPort": ${local.kafka_ui_port},
        "hostPort": ${local.kafka_ui_port}
      }
    ],
    "memory": 512,
    "cpu": 256,
    "logConfiguration": {
      "logDriver": "awslogs",
      "options": {
        "awslogs-group": "${aws_cloudwatch_log_group.kafka_ui_service.name}",
        "awslogs-region": "${var.aws_region}",
        "awslogs-stream-prefix": "${var.env_alias[var.env]}-${local.kafka_ui_name}"
      }
    },
    "environment": [
      {"name": "KAFKA_CLUSTERS_0_NAME", "value": "local"},
      {"name": "KAFKA_CLUSTERS_0_BOOTSTRAPSERVERS", "value": "${local.bootstrap_brokers_with_protocol}"},
      {"name": "KAFKA_CLUSTERS_0_PROPERTIES_SECURITY_PROTOCOL", "value": "PLAINTEXT"}
    ]
  }
]
DEFINITION
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  memory                   = 512
  cpu                      = 256
  execution_role_arn       = aws_iam_role.ecsTaskExecutionRole.arn
  task_role_arn            = aws_iam_role.ecsTaskExecutionRole.arn
}

resource "aws_cloudwatch_log_group" "kafka_ui_service" {
  name = "${var.project}/${var.instance}/${var.env_alias[var.env]}/ecs/${local.kafka_ui_name}"
  retention_in_days = 7 # Adjust as needed
}

module "kafka_ui_service" {
  source = "./ecs_app"

  project                   = var.project
  instance                  = var.instance
  env                       = var.env
  service_port              = local.kafka_ui_port
  # service_public_port       = 80 # Adjust as needed
  service_name              = local.kafka_ui_name
  ecs_cluster               = aws_ecs_cluster.this.id
  task_definition           = aws_ecs_task_definition.kafka_ui_task
  tags                      = {"service" = "KafkaUI", "project" = var.project}
  vpc_id                    = module.vpc.vpc.id
  service_subnets           = [module.kafkab_subnets.subnets[0].id, module.kafkab_subnets.subnets[1].id]
  alb_subnet_ids            = module.lb_subnets.subnets.*.id
  ingress_sg_ecs_rules      = local.kafka_ui_ingress_ecs_rules
  egress_sg_ecs_rules       = local.kafka_ui_egress_ecs_rules
  ingress_sg_rules          = local.kafka_ui_ingress_lb_rules
  egress_sg_rules           = local.kafka_ui_egress_lb_rules
  logging_s3_bucket         = aws_s3_bucket.alb-access-logs
  dns_zone_id               = aws_route53_zone.delegated.zone_id
  acm_certificate           = aws_acm_certificate.shared_public_lb
  service_discovery         = true

  health_check = {
    enabled             = true
    healthy_threshold   = 2
    interval            = 30
    path                = "/"
    matcher             = "200"
    port                = local.kafka_ui_port
    protocol            = "HTTP"
    timeout             = 5
    unhealthy_threshold = 2
  }
}