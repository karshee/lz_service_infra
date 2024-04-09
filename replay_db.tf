locals {

  replay_db_ingress_sg_rules = [
    {
      cidr_blocks = [lookup(module.cidr.cidr_blocks[var.instance][var.project], var.env)]
      from_port   = 5432
      to_port     = 5432
      protocol    = "tcp"
      description = "Access from vpc"
    }
  ]
  replay_db_egress_sg_rules = [
    {
      cidr_blocks = ["0.0.0.0/0"]
      from_port   = 5432
      to_port     = 5432
      protocol    = "tcp"
      description = "Access to Jackpots subnet"
    }
  ]
}


## AWS RDS DB ##
resource "aws_security_group" "rs_db_sg" {
  name        = "${local.replayservice_name}_${var.project}_${var.env}_db_sg"
  description = "Allow inbound traffic for DB"
  vpc_id      = module.vpc.vpc.id

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [lookup(module.cidr.cidr_blocks[var.instance][var.project], var.env)]
  }

  egress {
    description = "Allow all traffic out"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_db_subnet_group" "rs_rds_subnet_group" {
  name       = "${local.replayservice_name}_${var.project}_${var.env}_rds_subnet_group"
  subnet_ids = [module.private_subnets.subnets[0].id, module.private_subnets.subnets[1].id]
}

resource "aws_kms_key" "replay_rds" {
  description = "AWS managed key for ${var.env} replay RDS"
}

data "aws_db_snapshot" "specific_snapshot" {
  db_snapshot_identifier = "${local.replayservice_name}-encrypted-snapshot-1"
}

resource "aws_db_instance" "rs_db" {
  instance_class             = "db.t3.medium"
  snapshot_identifier        = data.aws_db_snapshot.specific_snapshot.id
  engine                     = "postgres"
  engine_version             = "12"
  allow_major_version_upgrade= true
  auto_minor_version_upgrade = false
  storage_encrypted          = true
  multi_az                   = false
  publicly_accessible        = false
  deletion_protection        = true
  skip_final_snapshot        = true
  final_snapshot_identifier  = "${var.instance}-${var.project}-airflow-rds-snapshot-${local.timestamp_sanitized}"
  identifier                 = "${local.replayservice_name}-${var.project}-${var.env}-db"
  vpc_security_group_ids     = [aws_security_group.rs_db_sg.id]
  db_subnet_group_name       = aws_db_subnet_group.rs_rds_subnet_group.name
  kms_key_id                 = aws_kms_key.replay_rds.arn
}

#############################################
#############################################


module "replay_db_aurora" {
  source = "./modules/aurora"

  instance                = var.instance
  project                 = var.project
  env                     = var.env
  env_alias               = var.env
  vpc                     = module.vpc.vpc
  backup_retention_period = 7
  default_db_name         = "replayservice"
  cid_prefix              = "replay"
  db_subnets              = module.private_subnets.subnets
  engine_mode             = "provisioned"
  engine_version          = "12"
  instance_configuration  = {
    instance_class   = "db.t3.medium"
    instance_count   = 2
    max_connections  = 1000
  }
  master_username         = "${local.replayservice_short_name}admin"
  port                    = 5432
  name                    = "replay"
  additional_users        = ["replayuser"]
  ingress_db_sg_rules     = local.replay_db_ingress_sg_rules
  egress_db_sg_rules      = local.replay_db_egress_sg_rules
  storage_encrypted       = true
  kms_key_id              = aws_kms_key.replay_rds.arn
  snapshot_identifier     = ""
}

#############################################
#############################################

#RDS Password#
resource "random_password" "rds_password" {
  length           = 16
  special          = true
  override_special = "_!%^"
}

resource "aws_secretsmanager_secret" "rds_password" {
  name = "${var.env}/rs/postgres/admin/password"
}

resource "aws_secretsmanager_secret_version" "rds_password" {
  secret_id     = aws_secretsmanager_secret.rds_password.id
  secret_string = random_password.rds_password.result
}

#Replay DB User management
resource "aws_iam_role" "update_db_users" {
  name = "update_db_users"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          AWS = [
            "arn:aws:iam::024059182542:user/TerraformSpokeAccounts",
            "arn:aws:iam::024059182542:user/AnsibleSpokeAccounts"
          ]
        },
        Action = "sts:AssumeRole"
      }
    ]
  })
}


resource "aws_iam_policy" "update_db_users_policy" {
  name        = "FullAccessPolicy"
  description = "A policy that allows full administrative access"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "*",
        Effect = "Allow",
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "full_access_attach" {
  role       = aws_iam_role.update_db_users.name
  policy_arn = aws_iam_policy.update_db_users_policy.arn
}

# Add users here, passwords and postgres roles will be created - permissions/roles assigned separately
locals {
  replay_users = toset(["replayuser"])
}

data "aws_secretsmanager_secret" "replayuser_password" {
  for_each         = local.replay_users
  name             = "${var.env}/${local.replayservice_short_name}/postgres/${each.key}/password"
}

data "aws_secretsmanager_secret_version" "replayuser_password_version" {
  for_each  = local.replay_users
  secret_id = data.aws_secretsmanager_secret.replayuser_password[each.key].id
}


# create the roles using the generated passwords
# role is assigned manually in the DB
resource "postgresql_role" "replay_role" {
  for_each = local.replay_users
  provider = postgresql.replay_db
  name     = each.key
  login    = true
  password = jsondecode(data.aws_secretsmanager_secret_version.replayuser_password_version[each.key].secret_string)["password"]

  depends_on = [
    aws_db_instance.rs_db
  ]

  lifecycle {
    ignore_changes = [
      roles
    ]
  }
}
