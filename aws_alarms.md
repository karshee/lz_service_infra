# AWS Alarms with TF Guide
AWS CloudWatch Alarms can be used to monitor metrics and send notifications based on the values of the metrics.

* Inside the [ecs_app/alarms](ecs_app/alarm.tf) file are defined the alarms applied to all the ECS services.
* For service-specific alarms, the alarms have to be defined in the service's `.tf` file.

## CloudWatch Metric Alarm
The resource `aws_cloudwatch_metric_alarm` can be used to create an alarm based on a metric.

```hcl
resource "aws_cloudwatch_metric_alarm" "round_interactions_unrecoverable_exception" {
  alarm_name          = "${var.instance}-XXXXX-${var.env}-round-interactions-unrecoverable-exception"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "1"
  metric_name         = "RoundInteractionsUnrecoverableException"
  namespace           = "JdbcConnectorsCustomMetrics"
  period              = "60"
  statistic           = "SampleCount"
  threshold           = "1"
  alarm_description   = "This alarm is triggered when Round Interactions JDBC Connector throws an uncaught and unrecoverable exception"
  alarm_actions       = [aws_sns_topic.jdbc_alert_topic.arn]
}
```

In this example the alarm will be triggered when the metric `RoundInteractionsUnrecoverableException` in the namespace `JdbcConnectorsCustomMetrics` has a value greater than or equal to `1`. 
When the alarm is triggered, it will send a notification to the SNS topic `jdbc_alert_topic`.

### Properties
| Property            | Description                                                                                |
|---------------------|--------------------------------------------------------------------------------------------|
| alarm_name          | The name of the alarm                                                                      |
| comparison_operator | The arithmetic operation to use when comparing the specified statistic and threshold       |
| evaluation_periods  | The number of periods over which data is compared to the specified threshold               |
| metric_name         | The name of the metric                                                                     |
| namespace           | The namespace of the metric                                                                |
| period              | The period in seconds over which the specified statistic is applied                        |
| statistic           | The statistic to apply to the alarm's associated metric                                    |
| threshold           | The value against which the specified statistic is compared                                |
| alarm_description   | The description of the alarm                                                               |
| alarm_actions       | The actions to execute when this alarm transitions to the ALARM state from any other state |


#### Comparison Operator Property
| Comparison Operator           | Description                                                                           |
|-------------------------------|---------------------------------------------------------------------------------------|
| GreaterThanOrEqualToThreshold | The alarm is triggered if the metric value is greater than or equal to the threshold. |
| GreaterThanThreshold          | The alarm is triggered if the metric value is greater than the threshold.             |
| LessThanThreshold             | The alarm is triggered if the metric value is less than the threshold.                |
| LessThanOrEqualToThreshold    | The alarm is triggered if the metric value is less than or equal to the threshold.    |


#### Statistic Property
The most common statistics are:

| Statistic   | Description                                                             |
|-------------|-------------------------------------------------------------------------|
| SampleCount | The count (number) of data points used for the statistical calculation. |
| Average     | The value of the specified statistic.                                   |
| Sum         | The sum of the values of the specified statistic.                       |
| Minimum     | The minimum value of the specified statistic.                           |
| Maximum     | The maximum value of the specified statistic.                           |

For more statistic options, see [Statistics Definitions](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/Statistics-definitions.html).


## CloudWatch Log Metric Filter
The resource `aws_cloudwatch_log_metric_filter` can be used to create a metric filter for a log group. 
The metric filter will search for a specific pattern in the log group and create a metric based on the pattern. 
The metric can then be used to create an alarm. 

```hcl
resource "aws_cloudwatch_log_metric_filter" "vanilla_interactions_unrecoverable_exception_metric_filter" {
  log_group_name = "${var.project}/${var.instance}/${var.env_alias[var.env]}/ecs/${local.replayjdbcconnector_name}"
  name           = "vanilla-interactions-unrecoverable-exception-metric-filter"
  pattern        = "ERROR JdbcSinkVanillaInteractions threw an uncaught and unrecoverable exception"

  metric_transformation {
    name      = "VanillaInteractionsUnrecoverableException"
    namespace = "JdbcConnectorsCustomMetrics"
    value     = "1"
  }
}
```

In this example the metric filter will search for the pattern `ERROR JdbcSinkVanillaInteractions threw an uncaught and unrecoverable exception` in the log group `log_group_name`. 
When the pattern is found, a metric named `VanillaInteractionsUnrecoverableException` will be created in the namespace `JdbcConnectorsCustomMetrics` with a value of `1`.


### Filter Properties

| Property       | Description                                                   |
|----------------|---------------------------------------------------------------|
| log_group_name | The name of the log group to associate the metric filter with |
| name           | The name of the metric filter                                 |
| pattern        | The pattern to search for in the log group                    |

#### Filter Metric Transformation Properties
The `metric_transformation` block contains the metric transformation properties of the metric filter.

| Property  | Description                        |
|-----------|------------------------------------|
| name      | The name of the metric             |
| namespace | The namespace of the metric        |
| value     | The value to publish to the metric |

## SNS Topic
An SNS Topic is a communication channel to send messages and notifications to subscribed endpoints.

The resource `aws_sns_topic_subscription` can be used to create a subscription to an SNS topic.
For all the services the sns email subscription is configured in the global [ecs_app/alarms](ecs_app/alarm.tf) file.

```hcl
resource "aws_sns_topic_subscription" "sns_email_subscriptions" {
  for_each = { for email in var.email_subscribers : email => email }

  topic_arn         = aws_sns_topic.alarm_sns_topic.arn
  protocol          = "email"
  endpoint          = each.value
  confirmation_timeout_in_minutes = 1
}
```

The only requirement per service is to define a list of subscribers' emails in the [fft_replay_dev.tfvars](fft_replay_dev.tfvars) file (for the dev environment) and the [fft_replay_prod.tfvars](fft_replay_prod.tfvars) file (for the prod environment).
```hcl
service_email_subscribers = ["user1@lnw.com", "user2@lnw.com"]
```

and in the service's `.tf` file, the `email_subscribers` variable is defined under the service module block.

```hcl
module "service" {
  source = "./ecs_app"
  
  ...
  email_subscribers         = var.service_email_subscribers
  ...
  }
}