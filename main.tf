terraform {
  required_version = "~> 1.5.7"
  backend "s3" {
  }
  required_providers {
    cloudflare = {
      source = "cloudflare/cloudflare"
      version = "~> 3.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1"
    }
    postgresql = {
      source  = "cyrilgdn/postgresql"
      version = "~> 1.15.0"
    }
    grafana = {
      source  = "grafana/grafana"
      version = "~> 1.24.0"
    }
  }
}

locals {
  tag_suffix  = "${var.account}-${var.ou}-${var.env}"
  assume_role = "${var.assume_role_name}${var.plan_only ? "PlanOnly" : ""}"
}

# Configure the AWS Provider & set region
provider "aws" {
  region = var.aws_region
  assume_role {
    role_arn = "arn:aws:iam::${var.aws_account_id}:role/${local.assume_role}"
  }
  default_tags {
    tags = {
      Environment  = var.env
      Name         = local.tag_suffix
      Division     = "SGDigital"
      map-migrated = "d-server-03vyezejfjvlqi"
    }
  }
}

data "aws_default_tags" "default" {}

# alias provider required for access resource in another account
provider "aws" {
  alias  = "network"
  region = var.aws_region
  assume_role {
    role_arn = "arn:aws:iam::${module.data.aws_account_number["network"]}:role/${local.assume_role}"
  }
}

## postgresql provider to create users in the DB
provider "postgresql" {
  alias    = "replay_db"
  scheme   = "postgres"
  host     = "localhost"
  username = "XXadmin"
  port     = 5450
  password = aws_secretsmanager_secret_version.rds_password.secret_string
  sslmode  = "disable"
  superuser = false
  database = local.replayservice_short_name
}

module "data" {
  source      = "./modules/data"
  account     = var.account
  env         = var.env
  instance    = var.instance
  ou          = var.ou
  aws_region  = var.aws_region
  assume_role = local.assume_role
}


module "cidr" {
  source = "./modules/cidr_blocks"
}

data "aws_caller_identity" "current" {}
