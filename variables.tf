variable "project" {
  type        = string
  description = "Project Name"
}

variable "instance" {
  type        = string
  description = "The instance of the infra e.g. gib"
}

variable "aws_account_id" {
  type        = string
  description = "The AWS Account ID"
}

variable "ou" {
  type        = string
  description = "Organisational Unit"
}

variable "account" {
  type        = string
  description = "The account within the OU"
}

variable "aws_region" {
  type = string
}

variable "az_count" {
  type    = number
  default = 1
}

variable "env" {
  type    = string
  default = "dev"
}

variable "plan_only" {
  type    = bool
  default = false
}

variable "assume_role_name" {
  type    = string
  default = "SGTerraformSpokeAccounts"
}

variable "ingress_allowed_cidrs" {
  type    = list(string)
  default = [
    "0.0.0.0/32",
    #Add relevant IP ranges here
  ]
}

variable "ig_ports" {
  type        = list(number)
  description = "list of ingress ports"
  default     = [22, 80, 8082]
}

variable "env_alias" {
  type    = map(any)
  default = {
    "prod"  = "prd",
    "dev"   = "dev"
  }
}

variable "default_instance_type" {
  description = "Default instance type for the environment"
  default     = "t3.micro"
}

variable "enable_red7" {
  type        = bool
  description = "enables EC2 migrated from old infra - red7"
  default     = false
}

variable "ecs_log_retention" {
  description = "Number of days to retain ecs logs"
}

variable "replay_service_tag" {
  type    = string
  default = "latest"
}

variable "replayschemaregistry_tag" {
  type    = string
  default = "latest"
}


variable "replayjdbcconnector_tag" {
  type    = string
  default = "latest"
}

variable "rs_allow_public" {
  type    = bool
  description = "allows public access to replay load balancer"
  default = false
}

variable "msk_public_access" {
  description = "Allow public access to MSK cluster"
  type = bool
  default = false
}

variable "kafka_broker_count" {
  description = "number of subnets/AZs to deploy kafka brokers in"
  type = number
  default = 3
}

variable "msk_config_standard" {
  type = string
  description = "Standard MSK cluster config"
  default = <<-PROPERTIES
num.partitions=2
transaction.state.log.replication.factor=2
transaction.state.log.min.isr=2
offsets.topic.replication.factor=2
    PROPERTIES
}

variable "msk_config_restricted" {
  type        = string
  description = "MSK cluster config for xxxx cluster"
  default     = <<-PROPERTIES
num.partitions=2
transaction.state.log.replication.factor=2
transaction.state.log.min.isr=2
offsets.topic.replication.factor=2
allow.everyone.if.no.acl.found=false
    PROPERTIES
}

variable "msk_cluster_restriction" {
  description = "Restrict the MSK cluster with allow.everyone.if.no.acl.found=false"
  type        = bool
  default     = false
}

variable "kafka_instance_type" {
  description = "Map of instance types"
  type        = string
  default     = "kafka.t3.small"
}


variable "replay_email_subscribers" {
  description = "List of email addresses to subscribe to the SNS topic regarding replay service"
  type        = list(string)
  default     = []
}
