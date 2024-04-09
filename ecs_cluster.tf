locals {
  ecs_cluster_name = "${var.project}-${var.env_alias[var.env]}-${var.instance}"
}

resource "aws_ecs_cluster" "this" {
  name = local.ecs_cluster_name

  setting {
      name  = "containerInsights"
      value = "enabled"
    }
}
