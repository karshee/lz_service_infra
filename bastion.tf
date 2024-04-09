data "aws_ami" "latest_amazon_linux_2023" {
  most_recent = true

  filter {
    name   = "name"
    values = ["al2023-*"]
  }

  owners = ["amazon"]
}

locals {
  bastionserver-port = 22
  user_data_script = <<-EOF
                      #!/bin/bash
                      sudo yum install -y https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/latest/linux_amd64/amazon-ssm-agent.rpm
                      sudo systemctl status amazon-ssm-agent
                    EOF
  bastionserver_ingress_rules = [
    {
      cidr_blocks = var.ingress_allowed_cidrs
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      description = "SSH ingress from offices"
    }
  ]
  bastionserver_egress_rules = [
    {
      cidr_blocks = ["0.0.0.0/0"]
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
      description = "Allow all ports"
    }
  ]
}

data "aws_iam_policy_document" "bastion-server-assume-role-policy" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

# bastion instance
module "bastion_server_instance" {
  source                = "./modules/app_instance"
  name                  = "bastionserver-0"
  env                   = var.env
  vpc_id                = module.vpc.vpc.id
  instance              = var.instance
  subnets               = [module.lb_subnets.subnets[0]]
  ami                   = "ami-01a90222dbf4gj033"
  instance_count        = 1
  instance_type         = "t2.micro"
  key_name              = "${var.env}-XXX-studio-fft-master"
  instance_profile_name = aws_iam_instance_profile.bastion-server.name
  egress_sg_rules       = local.bastionserver_egress_rules
  ingress_sg_rules      = local.bastionserver_ingress_rules
  user_data             = local.user_data_script
  volume_type           = "gp2"
  root_volume_size      = 256
}

# Role and instance profile
resource "aws_iam_role" "bastion-server" {
  name                = "bastion-${var.env_alias[var.env]}-${var.project}-${var.instance}"
  managed_policy_arns = [
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  ]
  assume_role_policy = data.aws_iam_policy_document.bastion-server-assume-role-policy.json
}

resource "aws_iam_instance_profile" "bastion-server" {
  name  = "bastion-${var.env_alias[var.env]}-${var.project}-${var.instance}"
  role = aws_iam_role.bastion-server.name
}

resource "aws_eip" "bastion_eip" {
  instance = module.bastion_server_instance.instance[0].id
  domain = "vpc"
}

data "aws_iam_policy_document" "ecs_execute_command_policy" {
  statement {
    actions = [
      "ecs:ExecuteCommand"
    ]

    resources = ["*"]
  }
}

resource "aws_iam_policy" "bastion_ecs_execute_command_policy" {
  name        = "BastionECSExecuteCommandPolicy"
  description = "Allows ECS ExecuteCommand on all tasks"
  policy      = data.aws_iam_policy_document.ecs_execute_command_policy.json
}

resource "aws_iam_role_policy_attachment" "bastion_ecs_execute_command_attachment" {
  role       = aws_iam_role.bastion-server.name
  policy_arn = aws_iam_policy.bastion_ecs_execute_command_policy.arn
}