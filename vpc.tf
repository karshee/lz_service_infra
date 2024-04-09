data "aws_availability_zones" "zone" {}

locals {
  name        = "${var.instance}-${var.env}"
  vpc_name    = "${local.name}-${local.tag_suffix}"
  private_dns = "${var.env_alias[var.env]}.${var.project}.${var.instance}"
}

######### Load Balancer Subnets ###########

module "lb_subnets" {
  source       = "./modules/subnet"
  vpc          = module.vpc.vpc
  name         = "lb-${var.account}-${var.env}"
  az_count     = var.az_count
  cidr_newbits = 5
  cidr_offset  = 27
}

#Create route tables for lb subnets
resource "aws_route_table" "public_lb" {
  vpc_id = module.vpc.vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = module.vpc.internet_gateway.id
  }

  route {
    cidr_block         = "10.44.176.0/21"
    transit_gateway_id = module.data.transit_gateway.id
  }

  tags = {
    Name = "lb-public-${var.env}"
  }
  depends_on = [module.lb_subnets]
}

#Associate public LB subnets with above route table
resource "aws_route_table_association" "public_lb" {
  count          = var.az_count
  subnet_id      = module.lb_subnets.subnets[count.index].id
  route_table_id = aws_route_table.public_lb.id
}

######### Private Subnets ###########
module "private_subnets" {
  source                  = "./modules/subnet"
  vpc                     = module.vpc.vpc
  name                    = "priv-${var.account}-${var.env}"
  az_count                = var.az_count
  cidr_newbits            = 5
  cidr_offset             = 9
  route_table_association = aws_route_table.pri
}

resource "aws_route_table" "pri" {
  vpc_id = module.vpc.vpc.id
  route {
    cidr_block         = "0.0.0.0/0"
    transit_gateway_id = module.data.transit_gateway.id
  }
  tags = {
    Name = "protected-${var.env}"
  }
}

#Associate PR subnet with PR route table
resource "aws_route_table_association" "pr" {
  count          = var.az_count
  subnet_id      = module.private_subnets.subnets[count.index].id
  route_table_id = aws_route_table.pri.id
}

######### Transit Gateway Subnets ###########
module "tgw_subnets" {
  source       = "./modules/subnet"
  vpc          = module.vpc.vpc
  name         = "tgw-${var.account}-${var.env}"
  az_count     = var.az_count
  cidr_newbits = 5
  cidr_offset  = 3
}

#Create route tables for TGW subnets
resource "aws_route_table" "tgw" {
  vpc_id = module.vpc.vpc.id
  route {
    cidr_block         = "0.0.0.0/0"
    transit_gateway_id = module.data.transit_gateway.id
  }
  tags = {
    Name = "tgw-${var.env}"
  }
  depends_on = [module.tgw_subnets]
}

#Associate TGW subnets with above route tables
resource "aws_route_table_association" "tgw" {
  count          = var.az_count
  subnet_id      = module.tgw_subnets.subnets[count.index].id
  route_table_id = aws_route_table.tgw.id
}

######### Kafka Broker Subnets ###########
module "kafkab_subnets" {
  source       = "./modules/subnet"
  vpc          = module.vpc.vpc
  name         = "kafkab-${var.account}-${var.env}"
  az_count     = var.kafka_broker_count
  cidr_newbits = 5
  cidr_offset  = 12
}

#Create route tables for TGW subnets
resource "aws_route_table" "kafkab" {
  vpc_id = module.vpc.vpc.id
  route {
    cidr_block         = "0.0.0.0/0"
    transit_gateway_id = module.data.transit_gateway.id
  }
  tags = {
    Name = "kafkab-${var.env}"
  }
  depends_on = [module.kafkab_subnets]
}

#Associate TGW subnets with above route tables
resource "aws_route_table_association" "kafkab" {
  count          = var.kafka_broker_count
  subnet_id      = module.kafkab_subnets.subnets[count.index].id
  route_table_id = aws_route_table.kafkab.id
}

######### VPC ###########
module "vpc" {
  source = "./modules/vpc"
  instance    = var.instance
  env         = var.env
  name        = "${var.instance}-${var.env}"
  ou          = var.ou
  account     = "replay"
  public      = true
  private_dns = "${var.env_alias[var.env]}.${var.project}.${var.instance}"
}

#Create Transit GW Attachment and associate it with TGW subnets
resource "aws_ec2_transit_gateway_vpc_attachment" "this" {
  subnet_ids         = module.tgw_subnets.subnets[*].id
  transit_gateway_id = module.data.transit_gateway.id
  vpc_id             = module.vpc.vpc.id
}

#acm certificate for public load balancer
resource "aws_acm_certificate" "shared_public_lb" {
  domain_name       = "*.${aws_route53_zone.delegated.name}"
  validation_method = "DNS"

  tags = {
    Name = "${var.project}-${var.env}-${var.instance}"
  }

  lifecycle {
    create_before_destroy = true
  }
}