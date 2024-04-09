variable "env" {
    description = "environment name"
    type        = string
}

variable "instance" {
    description = "instance name eg fft, nea or saf"
    type        = string
}

variable "project" {
    description = "project name"
    type        = string
}

variable "launch_type" {
  description = "ECS launch type"
  type        = string
  default     = "FARGATE"
}

variable "desired_count" {
  description = "number of ECS containers to run"
  type        = number
  default     = 1
}

variable "assign_public_ip" {
  description = "assign public IP to ECS containers"
  type        = bool
  default     = false
}

variable "service_port" {
  description = "container port to expose"
  type        = number
}

variable "service_public_port" {
  description = "Optional public port for the service"
  type        = number
  default     = null
}

variable "service_name" {
    description = "ECS service name"
    type        = string
}

variable "ecs_cluster" {
    description = "ECS cluster to deploy into"
    type        = string
}

variable "task_definition" {
    description = "ECS task definition to deploy"
}

variable "tags" {
    description = "tags to apply to resources"
    type        = map(string)
    default     = {}
}

variable "vpc_id" {
    description = "VPC to deploy into"
    type        = string
}

variable "service_subnets" {
    description = "subnets to deploy ecs into"
    type        = list(string)
}

variable "alb_subnet_ids" {
    description = "subnets to deploy load balancers into"
    type        = list(string)
  default       = []
}

variable "ingress_sg_rules" {
  description = "Internal ELB security group ingress rules"
  type = list(object({
    cidr_blocks = list(string)
    from_port   = number
    to_port     = number
    protocol    = string
    description = string
  }))
  default = []
}

variable "egress_sg_rules" {
  description = "Internal ELB security group egress rules"
  type = list(object({
    cidr_blocks = list(string)
    from_port   = number
    to_port     = number
    protocol    = string
    description = string
  }))
  default = []
}

variable "ingress_sg_ecs_rules" {
  description = "Internal ELB security group ingress rules"
  type = list(object({
    cidr_blocks = list(string)
    from_port   = number
    to_port     = number
    protocol    = string
    description = string
  }))
  default = []
}

variable "egress_sg_ecs_rules" {
  description = "Internal ELB security group egress rules"
  type = list(object({
    cidr_blocks = list(string)
    from_port   = number
    to_port     = number
    protocol    = string
    description = string
  }))
  default = []
}

variable "logging_s3_bucket" {
    description = "S3 bucket to store logs"
    default     = null
}

variable "access_logging" {
    description = "enable access logging"
    type        = bool
    default     = false
}

variable "default_action" {
    description = "default action for ALB"
    type        = string
    default     = "forward"
}

variable "dns_zone_id" {
    description = "DNS zone ID"
    type        = string
}

variable "ecs_log_retention" {
    description = "ECS log retention in days"
    type        = number
    default     = 7
}

variable "health_check" {
  description = "health check config"
  type = object({
    enabled             = bool
    healthy_threshold   = number
    interval            = number
    path                = string
    matcher             = string
    port                = number
    protocol            = string
    timeout             = number
    unhealthy_threshold = number
  })
  default = {
    enabled             = true
    healthy_threshold   = 2
    interval            = 60
    path                = "/"
    matcher             = "200"
    port                = 80
    protocol            = "HTTP"
    timeout             = 5
    unhealthy_threshold = 2
  }
}

variable "acm_certificate" {
  description = "ACM certificate object for https access"
  type        = any
  default     = {}
}

variable "create_lb" {
  description = "Whether to create the load balancer and its associated resources"
  type        = bool
  default     = true
}

variable "service_discovery" {
  description = "if service discovery should be enabled for the ECS service"
  type        = bool
  default     = false
}

variable "service_registry_arn" {
  description = "ARN of the service registry to associate with the ECS service"
  type        = string
  default     = ""
}

variable "high_request_threshold" {
  description = "The threshold for high request count per target"
  type        = number
  default     = 1000
}

variable "low_request_threshold" {
  description = "The threshold for low request count per target"
  type        = number
  default     = 500
}

variable "scale_out_cooldown" {
  description = "The amount of time, in seconds, after a scale-out activity completes before another scale-out activity can start"
  default     = 120
}

variable "scale_in_cooldown" {
  description = "The amount of time, in seconds, after a scale-in activity completes before another scale-in activity can start"
  default     = 120
}

variable "min_capacity" {
  description = "minimum amount of ECS containers running"
  default     = 1
}

variable "max_capacity" {
  description = "maximum amount of ECS containers running"
  default     = 10
}

variable "autoscaling_enable" {
  description = "Whether to enable autoscaling resources"
  type        = bool
  default     = false
}

variable "cloudflare_zone" {
  description = "The Cloudflare zone ID"
  default     = {}
}

variable "high_memory_threshold" {
  description = "The threshold for max memory utilization"
  type        = number
  default     = 90
}

variable "high_cpu_threshold" {
  description = "The threshold for max CPU utilization"
  type        = number
  default     = 90
}

variable "email_subscribers" {
  description = "List of email addresses to subscribe to the SNS topic"
  type        = list(string)
  default     = []
}

variable "region" {
  description   = "AWS region"
    type        = string
  default       = "eu-central-1"
}