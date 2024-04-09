locals {
  replayjdbcconnector_public_port       = 80
  replayjdbcconnector_port              = 8083
  replayjdbcconnector_jmx_port          = 9094
  replayjdbcconnector_image             = "024059182542.dkr.ecr.${var.aws_region}.amazonaws.com/${var.project}/${local.replayjdbcconnector_name}:${var.replayjdbcconnector_tag}"
  replayjdbcconnector_name              = "replay-jdbc-connector"
  replayjdbcconnector_short_name        = "rjc"

  replayjdbcconnector_ingress_lb_rules = [
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

  replayjdbcconnector_egress_lb_rules = [
    {
      cidr_blocks = ["0.0.0.0/0"]
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
      description = "Allow all egress traffic"
    }
  ]

  replayjdbcconnector_ingress_ecs_rules = [
    {
      cidr_blocks = [lookup(module.cidr.cidr_blocks[var.instance][var.project], var.env)]
      from_port   = 8083
      to_port     = 8083
      protocol    = "tcp"
      description = "Access from load balancer"
    },
    {
      cidr_blocks = [lookup(module.cidr.cidr_blocks[var.instance][var.project], var.env)]
      from_port   = 80
      to_port     = 80
      protocol    = "tcp"
      description = "Access from load balancer"
    },
    {
      cidr_blocks = [lookup(module.cidr.cidr_blocks[var.instance][var.project], var.env)]
      from_port   = 9092
      to_port     = 9096
      protocol    = "tcp"
      description = "kafka Access from VPC"
    },
    {
      cidr_blocks = [lookup(module.cidr.cidr_blocks[var.instance][var.project], var.env)]
      from_port   = 8081
      to_port     = 8081
      protocol    = "tcp"
      description = "schema-registry Access from VPC"
    },
    {
      cidr_blocks = [lookup(module.cidr.cidr_blocks[var.instance][var.project], var.env)]
      from_port   = 5432
      to_port     = 5432
      protocol    = "tcp"
      description = "access from DB"
    }
  ]

  replayjdbcconnector_egress_ecs_rules = [
    {
      cidr_blocks = ["0.0.0.0/0"]
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
      description = "Allow all egress traffic"
    }
  ]

  replayjdbcconnector_tags = {service = "RJC", jira = "GDMP-1391"}
}

resource "aws_ecs_task_definition" "rjc_app_task" {
  family                   = local.replayjdbcconnector_name
  container_definitions    = <<DEFINITION
  [
    {
      "name": "${local.replayjdbcconnector_name}",
      "image": "${local.replayjdbcconnector_image}",
      "essential": true,
      "portMappings": [
        {
          "containerPort": ${local.replayjdbcconnector_port},
          "hostPort": ${local.replayjdbcconnector_port}
        },
        {
          "containerPort": ${local.replayjdbcconnector_jmx_port},
          "hostPort": ${local.replayjdbcconnector_jmx_port}
        }
      ],
      "memory": 4096,
      "cpu": 2048,
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "${aws_cloudwatch_log_group.rjc_service.name}",
          "awslogs-region": "${var.aws_region}",
          "awslogs-stream-prefix": "${var.env_alias[var.env]}-${local.replayjdbcconnector_name}"
        }
    },
      "environment": [
        {
          "name": "CONNECT_BOOTSTRAP_SERVERS",
          "value": "${local.bootstrap_brokers}"},
        {
          "name": "CONNECT_REST_PORT",
          "value": "${local.replayjdbcconnector_port}"
        },
        {
          "name": "CONNECT_GROUP_ID",
          "value": "jdbc-sink-connector-group"
        },
        {
          "name": "CONNECT_CONFIG_STORAGE_TOPIC",
          "value": "jdbc-sink-configs"
        },
        {
          "name": "CONNECT_OFFSET_STORAGE_TOPIC",
          "value": "jdbc-sink-offsets"
        },
        {
          "name": "CONNECT_STATUS_STORAGE_TOPIC",
          "value": "jdbc-sink-status"
        },
        {
          "name": "CONNECT_CONFIG_STORAGE_REPLICATION_FACTOR",
          "value": "3"
        },
        {
          "name": "CONNECT_OFFSET_STORAGE_REPLICATION_FACTOR",
          "value": "3"
        },
        {
          "name": "CONNECT_STATUS_STORAGE_REPLICATION_FACTOR",
          "value": "3"
        },
        {
          "name": "CONNECT_KEY_CONVERTER",
          "value": "org.apache.kafka.connect.json.JsonConverter"
        },
        {
          "name": "CONNECT_VALUE_CONVERTER",
          "value": "io.confluent.connect.avro.AvroConverter"
        },
        {
          "name": "CONNECT_VALUE_CONVERTER_SCHEMA_REGISTRY_URL",
          "value": "http://replay-schema-registry.replay-schema-registry.local:8081"
        },
        {
          "name": "CONNECT_REST_ADVERTISED_HOST_NAME",
          "value": "localhost"
        },
        {
          "name": "MAX_RETRIES",
          "value": "50"
        },
        {
          "name": "REPLAY_DB_URL",
          "value": "${aws_db_instance.rs_db.endpoint}/${aws_db_instance.rs_db.db_name}"
        },
        {
          "name": "REPLAY_DB_USER",
          "value": "${aws_db_instance.rs_db.username}"
        },
        {
          "name": "ROUND_MAX_RETRIES",
          "value": "10"
        },
        {
          "name": "ROUND_RETRY_BACKOFF_MS",
          "value": "30000"
        },
        {
          "name": "VANILLA_MAX_RETRIES",
          "value": "10"
        },
        {
          "name": "VANILLA_RETRY_BACKOFF_MS",
          "value": "3000"
        }
      ],
      "secrets": [
          {
            "name": "REPLAY_DB_PASS",
            "valueFrom": "${aws_secretsmanager_secret.rds_password.arn}"
          }
        ],
      "dockerLabels" : {
        "ECS_PROMETHEUS_EXPORTER_PORT": "${local.replayjdbcconnector_jmx_port}",
        "Java_EMF_Metrics": "true"
      }
    }
  ]
  DEFINITION

  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  memory                   = 4096
  cpu                      = 2048
  execution_role_arn       = "${aws_iam_role.ecsTaskExecutionRole.arn}"
  task_role_arn            = "${aws_iam_role.ecsTaskExecutionRole.arn}"
  tags                     = local.replayjdbcconnector_tags
}

resource "aws_cloudwatch_log_group" "rjc_service" {
  name = "${var.project}/${var.instance}/${var.env_alias[var.env]}/ecs/${local.replayjdbcconnector_name}"
  retention_in_days = var.ecs_log_retention
}

resource "aws_sns_topic" "jdbc_alert_topic" {
  name = "${var.env}-${local.replayjdbcconnector_name}-alarms"
}

resource "aws_cloudwatch_log_metric_filter" "round_interactions_unrecoverable_exception_metric_filter" {
  log_group_name = "${var.project}/${var.instance}/${var.env_alias[var.env]}/ecs/${local.replayjdbcconnector_name}"
  name           = "round-interactions-unrecoverable-exception-metric-filter"
  pattern        = "ERROR JdbcSinkRoundInteractions threw an uncaught and unrecoverable exception"

  metric_transformation {
    name      = "RoundInteractionsUnrecoverableException"
    namespace = "JdbcConnectorsCustomMetrics"
    value     = "1"
  }
}

resource "aws_cloudwatch_metric_alarm" "round_interactions_unrecoverable_exception" {
  alarm_name          = "${var.instance}-replay-${var.env}-round-interactions-unrecoverable-exception"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "1"
  metric_name         = "RoundInteractionsUnrecoverableException"
  namespace           = "JdbcConnectorsCustomMetrics"
  period              = "60"
  statistic           = "SampleCount"
  threshold           = "1"
  alarm_description   = "This alarm is triggered when Round Interactions JDBC Connector throws an uncaught and unrecoverable exception"
  alarm_actions       = [aws_sns_topic.jdbc_alert_topic.arn]
}

resource "aws_cloudwatch_log_metric_filter" "vanilla_interactions_unrecoverable_exception_metric_filter" {
  log_group_name = "${var.project}/${var.instance}/${var.env_alias[var.env]}/ecs/${local.replayjdbcconnector_name}"
  name           = "vanilla-interactions-unrecoverable-exception-metric-filter"
  pattern        = "ERROR JdbcSinkVanillaInteractions threw an uncaught and unrecoverable exception"

  metric_transformation {
    name      = "VanillaInteractionsUnrecoverableException"
    namespace = "JdbcConnectorsCustomMetrics"
    value     = "1"
  }
}

resource "aws_cloudwatch_metric_alarm" "vanilla_interactions_unrecoverable_exception" {
  alarm_name          = "vanilla-interactions-unrecoverable-exception-${var.instance}-replay-${var.env}"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "1"
  metric_name         = "VanillaInteractionsUnrecoverableException"
  namespace           = "JdbcConnectorsCustomMetrics"
  period              = "60"
  statistic           = "SampleCount"
  threshold           = "1"
  alarm_description   = "This alarm is triggered when Vanilla Interactions JDBC Connector throws an uncaught and unrecoverable exception"
  alarm_actions       = [aws_sns_topic.jdbc_alert_topic.arn]
}

resource "aws_cloudwatch_metric_alarm" "jdbc_connectors_unstable" {
  alarm_name          = "${var.instance}-replay-${var.env}-jdbc-connectors-unstable"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "1"
  metric_name         = "JdbcConnectorsStatus.value"
  namespace           = "ReplayServiceCustomMetrics"
  period              = "60"
  statistic           = "Maximum"
  threshold           = "1"
  alarm_description   = "This alarm is triggered when jdbc connectors are not running properly"
  alarm_actions       = [aws_sns_topic.jdbc_alert_topic.arn]
}

module "replayjdbcconnector_service" {
  source = "./ecs_app"

  project                   = var.project
  instance                  = var.instance
  env                       = var.env
  service_port              = local.replayjdbcconnector_port
  service_public_port       = local.replayjdbcconnector_public_port
  service_name              = local.replayjdbcconnector_name
  ecs_cluster               = aws_ecs_cluster.this.id
  task_definition           = aws_ecs_task_definition.rjc_app_task
  tags                      = local.replayjdbcconnector_tags
  vpc_id                    = module.vpc.vpc.id
  service_subnets           = [module.tgw_subnets.subnets[0].id, module.tgw_subnets.subnets[1].id]
  alb_subnet_ids            = module.lb_subnets.subnets.*.id
  ingress_sg_rules          = local.replayjdbcconnector_ingress_lb_rules
  egress_sg_rules           = local.replayjdbcconnector_egress_lb_rules
  ingress_sg_ecs_rules      = local.replayjdbcconnector_ingress_ecs_rules
  egress_sg_ecs_rules       = local.replayjdbcconnector_egress_ecs_rules
  logging_s3_bucket         = aws_s3_bucket.alb-access-logs
  acm_certificate           = aws_acm_certificate.shared_public_lb
  dns_zone_id               = aws_route53_zone.delegated.zone_id
  service_discovery         = true
  email_subscribers         = var.replay_email_subscribers
  high_cpu_threshold        = 90
  high_memory_threshold     = 90

  health_check = {
    enabled             = true
    healthy_threshold   = 2
    interval            = 30
    path                = "/connectors"
    matcher             = "200"
    port                = local.replayjdbcconnector_port
    protocol            = "HTTP"
    timeout             = 20
    unhealthy_threshold = 10
  }
}

###################################################
## Lambda function to retrieve connectors status ##
###################################################
variable "enable_connector_status_lambda" {
  description = "Flag to enable or disable the connector status Lambda function"
  type        = bool
  default     = false
}

resource "aws_s3_bucket" "connector_status_lambda" {
  count  = var.enable_connector_status_lambda ? 1 : 0

  bucket = "${local.replayjdbcconnector_name}-${var.env}-${var.instance}-lambda"
}

resource "aws_s3_object" "connector_status_lambda_code" {
  count  = var.enable_connector_status_lambda ? 1 : 0

  bucket = aws_s3_bucket.connector_status_lambda[0].bucket
  key    = "connector_package.zip"
  source = "${path.module}/connector_status_lambda_pkg/connector_package.zip"
  etag   = filemd5("${path.module}/connector_status_lambda_pkg/connector_package.zip")
}

resource "aws_lambda_function" "connector_status_lambda" {
  count  = var.enable_connector_status_lambda ? 1 : 0

  function_name = "${local.replayjdbcconnector_name}-${var.env}-${var.instance}-status-lambda"

  s3_bucket         = aws_s3_bucket.connector_status_lambda[0].bucket
  s3_key            = aws_s3_object.connector_status_lambda_code[0].key
  source_code_hash  = filebase64sha256("${path.module}/connector_status_lambda_pkg/connector_package.zip")

  handler = "main"
  runtime = "go1.x"
  role    = aws_iam_role.lambda_exec.arn
  description = "Lambda function to send jdbc connector status to cloudwatch"

  environment {
    variables = {
      SNS_TOPIC_ARN       = aws_sns_topic.jdbc_alert_topic.arn
      CONNECTOR_BASE_URL  = "https://${local.replayjdbcconnector_name}.${var.env}.replay.${var.cloudflare_dns_zone}"
    }
  }

  vpc_config {
    subnet_ids         = module.lb_subnets.subnets.*.id
    security_group_ids = [module.replayjdbcconnector_service.security_group.id]
  }
}

resource "aws_iam_policy" "connector_status_lambda_policy" {
  name        = "${local.replayjdbcconnector_name}-${var.env}-${var.instance}-status-lambda-policy"
  description = "Policy for JDBC Connector Lambda Function"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Resource = "arn:aws:logs:${var.aws_region}:${var.aws_account_id}:*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "connector_status_lambda_policy_attach" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = aws_iam_policy.connector_status_lambda_policy.arn
}

resource "aws_cloudwatch_event_rule" "connector_lambda_every_30_minutes" {
  name        = "every-30-minutes"
  description = "Trigger every 30 minutes"
  schedule_expression = "rate(30 minutes)"
}

resource "aws_lambda_permission" "connector_lambda_allow_event_bridge" {
  count         = var.enable_connector_status_lambda ? 1 : 0
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.connector_status_lambda[0].function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.connector_lambda_every_30_minutes.arn
}

resource "aws_cloudwatch_event_target" "invoke_connector_lambda_every_30_minutes" {
  count     = var.enable_connector_status_lambda ? 1 : 0
  rule      = aws_cloudwatch_event_rule.connector_lambda_every_30_minutes.name
  target_id = "InvokeLambdaEvery30Minutes"
  arn       = aws_lambda_function.connector_status_lambda[0].arn
}