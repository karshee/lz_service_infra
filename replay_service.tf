locals {
  replayservice_public_port      = 80
  replayservice_port             = 8080
  replayservice_image            = "120482309409.dkr.ecr.${var.aws_region}.amazonaws.com/${var.project}/${local.replayservice_name}:${var.replay_service_tag}"
  replayservice_name             = "replayservice"
  replayservice_short_name       = "rs"
  timestamp_sanitized            = replace(timestamp(), "/[- TZ:]/", "")
  replayservice_db_username      = "${local.replayservice_short_name}admin"
  replayservice_ingress_lb_rules = concat([
    {
      cidr_blocks = [lookup(module.cidr.cidr_blocks[var.instance][var.project], var.env)]
      from_port   = 80
      to_port     = 80
      protocol    = "tcp"
      description = "HTTP Access from VPC"
    },
    {
      cidr_blocks = data.cloudflare_ip_ranges.cloudflare.ipv4_cidr_blocks
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      description = "HTTPS Access from public Cloudflare Edge Locations"
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
  ],

    #OPTIONAL#
    #Used when we want to allow public access to the service
    #To use this, set var.bsu_allow_public to true in tfvars
    var.rs_allow_public ? local.public_https_rule : [],
    var.rs_allow_public ? local.public_http_rule : []
  )

  public_https_rule = [
    {
      cidr_blocks = ["0.0.0.0/0"]
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      description = "for HTTPS access"
    }
  ]

  public_http_rule = [
    {
      cidr_blocks = ["0.0.0.0/0"]
      from_port   = 80
      to_port     = 80
      protocol    = "tcp"
      description = "for HTTP checks"
    }
  ]

  replayservice_egress_lb_rules = [
    {
      cidr_blocks = ["0.0.0.0/0"]
      from_port   = 8080
      to_port     = 8080
      protocol    = "tcp"
      description = "Access for health check"
    },
    {
      cidr_blocks = ["0.0.0.0/0"]
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      description = "for health checks"
    },
  ]
  replayservice_ingress_ecs_rules = [
    {
      cidr_blocks = [lookup(module.cidr.cidr_blocks[var.instance][var.project], var.env)]
      from_port   = 8080
      to_port     = 8080
      protocol    = "tcp"
      description = "HTTP Access from load balancer"
    },
    {
      cidr_blocks = [lookup(module.cidr.cidr_blocks[var.instance][var.project], var.env)]
      from_port   = 80
      to_port     = 80
      protocol    = "tcp"
      description = "Access to ECR"
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
      from_port   = 5432
      to_port     = 5432
      protocol    = "tcp"
      description = "access from DB"
    }
  ]
  replayservice_egress_ecs_rules = [
    {
      cidr_blocks = ["0.0.0.0/0"]
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
      description = "Allow all egress traffic"
    }
  ]
}

resource "aws_ecs_task_definition" "rs_app_task" {
  family                   = local.replayservice_name
  container_definitions    = <<DEFINITION
  [
    {
      "name": "${local.replayservice_name}",
      "image": "${local.replayservice_image}",
      "essential": true,
      "portMappings": [
        {
          "containerPort": ${local.replayservice_port},
          "hostPort": ${local.replayservice_port}
        }
      ],
      "memory": 512,
      "cpu": 256,
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "${aws_cloudwatch_log_group.rs_service.name}",
          "awslogs-region": "${var.aws_region}",
          "awslogs-stream-prefix": "${var.env_alias[var.env]}-${local.replayservice_name}"
        }
      },
      "secrets": [
        {
          "name": "SPRING_DATASOURCE_PASSWORD",
          "valueFrom": "${data.aws_secretsmanager_secret.replayuser_password["replayuser"].arn}:password::"
        },
        {
          "name": "AWS_CREDENTIALS_ACCESS_KEY",
          "valueFrom": "${data.aws_secretsmanager_secret.cloudwatch_access_key.arn}:access-key::"
        },
        {
          "name": "AWS_CREDENTIALS_SECRET_KEY",
          "valueFrom": "${data.aws_secretsmanager_secret.cloudwatch_secret_key.arn}:secret-key::"
        }
      ],
      "environment": [
        {
          "name": "SPRING_DATASOURCE_URL",
          "value": "jdbc:postgresql://${aws_db_instance.rs_db.endpoint}/${local.replayservice_short_name}"
        },
        {
          "name": "SPRING_DATASOURCE_USERNAME",
          "value": "replayuser"
        },
        {
          "name": "REPLAY_JDBC_CONNECTOR_URL",
          "value": "http://replay-jdbc-connector.replay-jdbc-connector.local:8083"
        },
        {
          "name": "REPLAY_JDBC_CONNECTOR_CONNECTORS",
          "value": "JdbcSinkRoundInteractions,JdbcSinkVanillaInteractions"
        }
      ]
    }
  ]
  DEFINITION
  requires_compatibilities = ["FARGATE"] # use Fargate as the launch type
  network_mode             = "awsvpc"    # add the AWS VPN network mode as this is required for Fargate
  memory                   = 2048
  cpu                      = 1024      # Specify the CPU the container requires
  execution_role_arn       = "${aws_iam_role.ecsTaskExecutionRole.arn}"
  task_role_arn            = "${aws_iam_role.ecsTaskExecutionRole.arn}"
}

resource "aws_cloudwatch_log_group" "rs_service" {
  name              = "${var.project}/${var.instance}/${var.env_alias[var.env]}/ecs/${local.replayservice_name}"
  retention_in_days = var.ecs_log_retention
}

resource "aws_sns_topic" "replayservice_alert_topic" {
  name = "${var.env}-${local.replayservice_name}-alarms"
}

resource "aws_cloudwatch_log_metric_filter" "replay_service_jdbc_connector_failure_metric_filter" {
  log_group_name = "${var.project}/${var.instance}/${var.env_alias[var.env]}/ecs/${local.replayservice_name}"
  name           = "replay-service-jdbc-connector-failure-metric-filter"
  pattern        = "JDBC Connectors are not running properly"

  metric_transformation {
    name      = "ReplayServiceJDBCConnectorFailure"
    namespace = "ReplayServiceCustomMetrics"
    value     = "1"
  }
}

resource "aws_cloudwatch_metric_alarm" "replay_service_jdbc_connector_failure" {
  alarm_name          = "${var.instance}-xxxxx-${var.env}-replay-service-jdbc-connector-failure"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "1"
  metric_name         = "ReplayServiceJDBCConnectorFailure"
  namespace           = "ReplayServiceCustomMetrics"
  period              = "60"
  statistic           = "SampleCount"
  threshold           = "1"
  alarm_description   = "This alarm is triggered when JDBC connectors are not configured properly"
  alarm_actions       = [aws_sns_topic.replayservice_alert_topic.arn]
}

resource "aws_cloudwatch_log_metric_filter" "replay_service_jdbc_connector_communication_failure_metric_filter" {
  log_group_name = "${var.project}/${var.instance}/${var.env_alias[var.env]}/ecs/${local.replayservice_name}"
  name           = "replay-service-jdbc-connector-communication-failure-metric-filter"
  pattern        = "Error occurred while communicating with JDBC connectors"

  metric_transformation {
    name      = "ReplayServiceJDBCConnectorCommunicationFailure"
    namespace = "ReplayServiceCustomMetrics"
    value     = "1"
  }
}

resource "aws_cloudwatch_metric_alarm" "replay_service_jdbc_connector_communication_failure" {
  alarm_name          = "${var.instance}-replay-${var.env}-replay-service-jdbc-connector-communication-failure"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "1"
  metric_name         = "ReplayServiceJDBCConnectorCommunicationFailure"
  namespace           = "ReplayServiceCustomMetrics"
  period              = "60"
  statistic           = "SampleCount"
  threshold           = "1"
  alarm_description   = "This alarm is triggered when there is a JDBC connectors communication failure"
  alarm_actions       = [aws_sns_topic.replayservice_alert_topic.arn]
}

resource "aws_cloudwatch_log_metric_filter" "replay_service_application_average_response_time_filter" {
  log_group_name = "${var.project}/${var.instance}/${var.env_alias[var.env]}/ecs/${local.replayservice_name}"
  name           = "replay-service-application-average-response-time-filter"
  pattern        = "\"RequestResponse\" ispresent(response.duration)"

  metric_transformation {
    name      = "ReplayServiceApplicationAverageResponseTime"
    namespace = "ReplayServiceCustomMetrics"
    value     = "substr(response.duration, 0, strlen(response.duration) - 2)"
    default_value = 0
  }
}

resource "aws_cloudwatch_metric_alarm" "replay_service_application_average_response_time" {
  alarm_name          = "${var.instance}-replay-${var.env}-replay-service-application-average-response-time"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "1"
  metric_name         = "ReplayServiceApplicationAverageResponseTime"
  namespace           = "ReplayServiceCustomMetrics"
  period              = "60"
  statistic           = "Average"
  threshold           = "60000"
  alarm_description   = "This alarm is triggered when application response time exceed the configured threshold"
  alarm_actions       = [aws_sns_topic.replayservice_alert_topic.arn]
}

module "replay_service" {
  source = "./ecs_app"

  project                   = var.project
  instance                  = var.instance
  env                       = var.env
  service_port              = local.replayservice_port
  service_public_port       = local.replayservice_public_port
  service_name              = local.replayservice_name
  ecs_cluster               = aws_ecs_cluster.this.id
  task_definition           = aws_ecs_task_definition.rs_app_task
  acm_certificate           = aws_acm_certificate.shared_public_lb
  vpc_id                    = module.vpc.vpc.id
  service_subnets           = [module.tgw_subnets.subnets[0].id, module.tgw_subnets.subnets[1].id]
  alb_subnet_ids            = module.lb_subnets.subnets.*.id
  ingress_sg_rules          = local.replayservice_ingress_lb_rules
  egress_sg_rules           = local.replayservice_egress_lb_rules
  ingress_sg_ecs_rules      = local.replayservice_ingress_ecs_rules
  egress_sg_ecs_rules       = local.replayservice_egress_ecs_rules
  logging_s3_bucket         = aws_s3_bucket.alb-access-logs
  dns_zone_id               = aws_route53_zone.delegated.zone_id
  cloudflare_zone           = data.cloudflare_zone.public
  email_subscribers         = var.replay_email_subscribers
  high_cpu_threshold        = 90
  high_memory_threshold     = 90

  #autoscaling
  autoscaling_enable        = true

  health_check = {
    enabled             = true
    healthy_threshold   = 2
    interval            = 30
    path                = "/api/actuator/health"
    matcher             = "200"
    port                = local.replayservice_port
    protocol            = "HTTP"
    timeout             = 5
    unhealthy_threshold = 2
  }
}

data "aws_secretsmanager_secret" "cloudwatch_access_key" {
  name             = "${var.env}/${local.replayservice_name}/cloudwatch/metrics/access-key"
}

data "aws_secretsmanager_secret" "cloudwatch_secret_key" {
  name             = "${var.env}/${local.replayservice_name}/cloudwatch/metrics/secret-key"
}

################################################
## Lambda function to replay the duration e2e ##
################################################
variable "enable_replay_duration_lambda" {
  description = "Flag to enable or disable the replay duration Lambda function"
  type        = bool
  default     = false
}

resource "aws_s3_bucket" "replay_duration_lambda" {
  count = var.enable_replay_duration_lambda ? 1 : 0

  bucket = "${local.replayservice_name}-${var.env}-${var.instance}-lambda"
}

resource "aws_s3_object" "lambda_code" {
  count = var.enable_replay_duration_lambda ? 1 : 0

  bucket = aws_s3_bucket.replay_duration_lambda[0].bucket
  key    = "package.zip"
  source = "${path.module}/replay_duration_lambda_pkg/package.zip"
  etag   = filemd5("${path.module}/replay_duration_lambda_pkg/package.zip")
}

resource "aws_lambda_function" "replay_duration_lambda" {
  count = var.enable_replay_duration_lambda ? 1 : 0

  function_name = "${local.replayservice_name}-${var.env}-${var.instance}-duration-lambda"

  s3_bucket         = aws_s3_bucket.replay_duration_lambda[0].bucket
  s3_key            = aws_s3_object.lambda_code[0].key
    source_code_hash  = filebase64sha256("${path.module}/replay_duration_lambda_pkg/package.zip")

  handler     = "main"
  runtime     = "go1.x"
  role        = aws_iam_role.lambda_exec.arn
  description = "Lambda function to send replay response time to cloudwatch"

  environment {
    variables = {
      DB_HOST             = aws_db_instance.rs_db.endpoint
      DB_PORT             = 5432
      DB_NAME             = aws_db_instance.rs_db.db_name
      DB_USERNAME         = aws_db_instance.rs_db.username
      DATABASE_SECRET_ARN = data.aws_secretsmanager_secret.replayuser_password["replayuser"].arn
    }
  }

  vpc_config {
    subnet_ids         = module.lb_subnets.subnets.*.id
    security_group_ids = [module.replay_service.security_group.id]
  }
}

resource "aws_iam_role" "lambda_exec" {
  name = "${var.env}-${var.instance}-lambda-exec-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "lambda.amazonaws.com"
        },
      },
    ],
  })
}

resource "aws_iam_policy" "replay_duration_lambda_policy" {
  name        = "${local.replayservice_name}-${var.env}-${var.instance}-duration-lambda-policy"
  description = "Policy for Replay Lambda Function"

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
      },
      {
        Effect = "Allow",
        Action = [
          "cloudwatch:PutMetricData",
          "ec2:CreateNetworkInterface",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DeleteNetworkInterface",
        ],
        Resource = "*"
      },
      {
        Effect = "Allow",
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret",
        ],
        Resource = [
          aws_secretsmanager_secret.rds_password.arn,
        ]
      },
      {
        Effect = "Allow",
        Action = [
          "rds-db:connect",
        ],
        Resource = "arn:aws:rds-db:${var.aws_region}:${var.aws_account_id}:*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "replay_duration_lambda_policy_attach" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = aws_iam_policy.replay_duration_lambda_policy.arn
}

resource "aws_cloudwatch_event_rule" "every_30_minutes" {
  name        = "every-30-minutes"
  description = "Trigger every 30 minutes"
  schedule_expression = "rate(30 minutes)"
}

resource "aws_lambda_permission" "allow_event_bridge" {
  count = var.enable_replay_duration_lambda ? 1 : 0
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.replay_duration_lambda[0].function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.every_30_minutes.arn
}

resource "aws_cloudwatch_event_target" "invoke_lambda_every_30_minutes" {
  count = var.enable_replay_duration_lambda ? 1 : 0
  rule      = aws_cloudwatch_event_rule.every_30_minutes.name
  target_id = "InvokeLambdaEvery30Minutes"
  arn       = aws_lambda_function.replay_duration_lambda[0].arn
}