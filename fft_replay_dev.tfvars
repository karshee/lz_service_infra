project = "replay-service"

aws_account_id = "12345678910"

az_count = 3

default_instance_type = "t2.nano"

enable_red7 = true

ecs_log_retention = 30

# dev images of services - short git commit IDs

replay_service_tag = "e956da82"

replayjdbcconnector_tag = "3aaabedd"

replayschemaregistry_tag = "ea80db7d"

# Email alarm/alert SNS subscriber list of emails
replay_email_subscribers = ["example@gmail.com"]

msk_cluster_restriction = false

enable_connector_status_lambda = false
enable_replay_duration_lambda = false

