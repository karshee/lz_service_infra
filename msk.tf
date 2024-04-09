locals {
  bootstrap_brokers                     = module.msk.msk_cluster.bootstrap_brokers
  bootstrap_scram_brokers               = module.msk.msk_cluster.bootstrap_brokers_sasl_scram
  msk_cluster_name                      = module.msk.msk_cluster.cluster_name

  msk_ingress_sg_rules = [
    {
      cidr_blocks = var.ingress_allowed_cidrs
      from_port   = 9092
      to_port     = 9096
      protocol    = "tcp"
      description = "kafka Access"
    },
    {
      cidr_blocks = [module.vpc.vpc.cidr_block]
      from_port   = 9092
      to_port     = 9092
      protocol    = "tcp"
      description = "Brokers - no authentication"
    },
    {
      cidr_blocks = [module.vpc.vpc.cidr_block]
      from_port   = 9094
      to_port     = 9094
      protocol    = "tcp"
      description = "Brokers - TLS"
    },
    {
      cidr_blocks = [module.vpc.vpc.cidr_block]
      from_port   = 9096
      to_port     = 9096
      protocol    = "tcp"
      description = "Brokers - SASL-SCRAM"
    }
  ]
  msk_egress_sg_rules = [
    {
      cidr_blocks = ["0.0.0.0/0"]
      from_port   = 0
      to_port     = 65535
      protocol    = "tcp"
      description = "Allow all traffic"
    },
  ]
}
resource "aws_sns_topic" "msk_alarm_sns_topic" {
  name = "${local.msk_cluster_name}-alarms"
}

resource "aws_cloudwatch_metric_alarm" "high_cpu_utilization" {
  count               = var.kafka_broker_count

  alarm_name          = "high-cpu-utilization-broker-${count.index + 1}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CpuUser"
  namespace           = "AWS/Kafka"
  period              = "60"
  statistic           = "Average"
  threshold           = "90"
  alarm_description   = "This alarm triggers when CPU utilization exceeds 90% over 2 periods (2 min)"
  alarm_actions       = [aws_sns_topic.msk_alarm_sns_topic.arn]

  dimensions = {
    ClusterName = local.msk_cluster_name
    "Broker ID" = count.index + 1
  }

  treat_missing_data = "notBreaching"
}

resource "aws_cloudwatch_metric_alarm" "high_memory_utilization" {
  count               = var.kafka_broker_count

  alarm_name          = "high-memory-utilization-broker-${count.index + 1}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "MemoryUsed"
  namespace           = "AWS/Kafka"
  period              = "60"
  statistic           = "Average"
  threshold           = "90"
  alarm_description   = "This alarms triggers when memory utilization exceeds 90% over 2 periods (2 min)"
  alarm_actions       = [aws_sns_topic.msk_alarm_sns_topic.arn]

  dimensions = {
    ClusterName = local.msk_cluster_name
    "Broker ID" = count.index + 1
  }

  treat_missing_data = "notBreaching"
}

resource "aws_cloudwatch_metric_alarm" "high_disc_usage" {
  count               = var.kafka_broker_count

  alarm_name          = "high-disc-usage-broker-${count.index + 1}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "KafkaDataLogsDiskUsed"
  namespace           = "AWS/Kafka"
  period              = "60"
  statistic           = "Average"
  threshold           = "90"
  alarm_description   = "This alarm triggers when disk utilization exceeds 90% over 2 periods (2 min)"
  alarm_actions       = [aws_sns_topic.msk_alarm_sns_topic.arn]

  dimensions = {
    ClusterName = local.msk_cluster_name
    "Broker ID" = count.index + 1
  }

  treat_missing_data = "notBreaching"
}

resource "aws_cloudwatch_metric_alarm" "msk_controller_count" {
  alarm_name          = "msk-controller-count"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  threshold           = 1
  alarm_description   = "This alarm triggers when there is less than 1 active controller in the cluster over 1 period (1 min)"
  alarm_actions       = [aws_sns_topic.msk_alarm_sns_topic.arn]
  treat_missing_data  = "notBreaching"

  dimensions = {
    ClusterName = local.msk_cluster_name
  }

  namespace   = "AWS/Kafka"
  metric_name = "ActiveControllerCount"
  period      = 60
  statistic   = "Minimum"
}

module "msk" {
  source                   = "./modules/msk"
  env                      = var.env_alias[var.env]
  instance                 = var.instance
  project                  = var.project
  vpc_id                   = module.vpc.vpc.id
  instance_type            = var.kafka_instance_type
  broker_subnets_ids       = module.kafkab_subnets.subnets[*].id
  ingress_sg_rules         = local.msk_ingress_sg_rules
  egress_sg_rules          = local.msk_egress_sg_rules
  kafka_version            = "2.8.1"
  client_broker_encryption = "TLS_PLAINTEXT"
  phz_id                   = module.vpc.phz.id
  msk_config               = var.msk_config_standard
  cluster_users            = ["schema-registry","jdbc-connector","debezium"]
  public_access            = var.msk_public_access
  unauthenticated_clients  = true
}
#
#module "apps_topics_acls" {
#  source                = "./modules/msk_topics_acls"
#  topics                = local.topics
#  bootstrap_servers     = module.msk_test.msk_cluster.bootstrap_brokers_sasl_scram
#  provisioning_user     = "kafka"
#  provisioning_password = jsondecode(module.msk_test.msk_tfuser.secret_version.secret_string)["password"]
#}