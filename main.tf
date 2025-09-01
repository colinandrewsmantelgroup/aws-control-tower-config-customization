# Zip all Python files into a single archive
data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "lambda_functions.zip"

  source {
    content  = file("${path.module}/ct_configrecorder_override_producer.py")
    filename = "ct_configrecorder_override_producer.py"
  }

  source {
    content  = file("${path.module}/ct_configrecorder_override_consumer.py")
    filename = "ct_configrecorder_override_consumer.py"
  }

  source {
    content  = file("${path.module}/cfnresponse.py")
    filename = "cfnresponse.py"
  }
}

# Upload the zip file to S3
resource "aws_s3_object" "lambda_zip" {
  bucket      = var.source_s3_bucket
  key         = var.lambda_s3_key
  source      = data.archive_file.lambda_zip.output_path
  source_hash = data.archive_file.lambda_zip.output_base64sha256

  # Ensure the zip file is created before attempting upload
  depends_on = [data.archive_file.lambda_zip]
}

resource "aws_sns_topic" "lambda_alerts" {
  name = local.sns_names.lambda_alerts
  
  tags = local.resource_tags.sns_alerts
}

# SNS Topic Policy to allow CloudWatch to publish messages
resource "aws_sns_topic_policy" "lambda_alerts_policy" {
  arn = aws_sns_topic.lambda_alerts.arn
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCloudWatchToPublish"
        Effect = "Allow"
        Principal = {
          Service = "cloudwatch.amazonaws.com"
        }
        Action   = "SNS:Publish"
        Resource = aws_sns_topic.lambda_alerts.arn
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })
}

# Add email subscription (replace with your email)
resource "aws_sns_topic_subscription" "lambda_alerts_email" {
  topic_arn = aws_sns_topic.lambda_alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email_address
}

# Shared CloudWatch Log Group for Lambda functions
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = local.cloudwatch_names.lambda_logs
  retention_in_days = 30

  tags = local.resource_tags.cloudwatch_logs
}

resource "aws_sqs_queue" "config_recorder" {
  name                       = local.sqs_names.config_recorder
  visibility_timeout_seconds = 180
  delay_seconds              = 5
  kms_master_key_id          = "alias/aws/sqs"
  
  tags = local.resource_tags.sqs_queue
}

resource "aws_lambda_function" "producer_lambda" {
  function_name                  = local.lambda_names.producer
  role                           = aws_iam_role.producer_lambda_execution_role.arn
  handler                        = "ct_configrecorder_override_producer.lambda_handler"
  runtime                        = "python3.12"
  memory_size                    = 128
  timeout                        = 300
  architectures                  = ["x86_64"]
  reserved_concurrent_executions = 1
  environment {
    variables = {
      EXCLUDED_ACCOUNTS = var.excluded_accounts
      LOG_LEVEL         = "INFO"
      SQS_URL           = aws_sqs_queue.config_recorder.id
    }
  }
  s3_bucket        = var.source_s3_bucket
  s3_key           = var.lambda_s3_key
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  depends_on       = [aws_s3_object.lambda_zip, aws_cloudwatch_log_group.lambda_logs]
  logging_config {
    log_group  = aws_cloudwatch_log_group.lambda_logs.name
    log_format = "JSON"
  }
  
  tags = local.resource_tags.lambda_producer
}

resource "aws_lambda_function" "consumer_lambda" {
  function_name                  = local.lambda_names.consumer
  role                           = aws_iam_role.consumer_lambda_execution_role.arn
  handler                        = "ct_configrecorder_override_consumer.lambda_handler"
  runtime                        = "python3.12"
  memory_size                    = 128
  timeout                        = 180
  architectures                  = ["x86_64"]
  reserved_concurrent_executions = 10
  environment {
    variables = {
      LOG_LEVEL                                           = "INFO"
      CONFIG_RECORDER_STRATEGY                            = var.config_recorder_strategy
      CONFIG_RECORDER_OVERRIDE_DAILY_RESOURCE_LIST        = var.config_recorder_daily_resource_types
      CONFIG_RECORDER_OVERRIDE_DAILY_GLOBAL_RESOURCE_LIST = var.config_recorder_daily_global_resource_types
      CONFIG_RECORDER_OVERRIDE_EXCLUDED_RESOURCE_LIST     = var.config_recorder_excluded_resource_types
      CONFIG_RECORDER_OVERRIDE_INCLUDED_RESOURCE_LIST     = var.config_recorder_included_resource_types
      CONFIG_RECORDER_DEFAULT_RECORDING_FREQUENCY         = var.config_recorder_default_recording_frequency
      CONTROL_TOWER_HOME_REGION                           = data.aws_region.current.region
    }
  }
  s3_bucket        = var.source_s3_bucket
  s3_key           = var.lambda_s3_key
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  depends_on       = [aws_s3_object.lambda_zip, aws_cloudwatch_log_group.lambda_logs]
  logging_config {
    log_group  = aws_cloudwatch_log_group.lambda_logs.name
    log_format = "JSON"
  }
  
  tags = local.resource_tags.lambda_consumer
}

resource "aws_iam_role" "producer_lambda_execution_role" {
  name = local.iam_role_names.producer_execution
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
  
  tags = local.common_tags
}

resource "aws_iam_role_policy" "producer_lambda_policy" {
  name = local.iam_policy_names.producer
  role = aws_iam_role.producer_lambda_execution_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["cloudformation:ListStackInstances"]
        Resource = "arn:aws:cloudformation:*:*:stackset/AWSControlTowerBP-BASELINE-CONFIG:*"
      },
      {
        Effect = "Allow"
        Action = [
          "sqs:DeleteMessage",
          "sqs:ReceiveMessage",
          "sqs:SendMessage",
          "sqs:GetQueueAttributes"
        ]
        Resource = aws_sqs_queue.config_recorder.arn
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "${aws_cloudwatch_log_group.lambda_logs.arn}:*"
      }
    ]
  })
}

resource "aws_iam_role" "consumer_lambda_execution_role" {
  name = local.iam_role_names.consumer_execution
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
  
  tags = local.common_tags
}

resource "aws_iam_role_policy" "consumer_lambda_policy" {
  name = local.iam_policy_names.consumer
  role = aws_iam_role.consumer_lambda_execution_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["sts:AssumeRole"]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "sqs:DeleteMessage",
          "sqs:ReceiveMessage",
          "sqs:SendMessage",
          "sqs:GetQueueAttributes"
        ]
        Resource = aws_sqs_queue.config_recorder.arn
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "${aws_cloudwatch_log_group.lambda_logs.arn}:*"
      }
    ]
  })
}

resource "aws_lambda_event_source_mapping" "consumer_lambda_event_source_mapping" {
  event_source_arn = aws_sqs_queue.config_recorder.arn
  function_name    = aws_lambda_function.consumer_lambda.arn
  batch_size       = 1
  enabled          = true
}

resource "aws_cloudwatch_event_rule" "producer_event_trigger" {
  name           = local.event_rule_names.producer_trigger
  description    = "Rule to trigger config recorder override producer lambda"
  event_bus_name = "default"
  event_pattern  = <<EOF
{
  "source": ["aws.controltower"],
  "detail-type": ["AWS Service Event via CloudTrail"],
  "detail": {
    "eventName": ["UpdateLandingZone", "CreateManagedAccount", "UpdateManagedAccount"]
  }
}
EOF
  state          = "ENABLED"
  
  tags = local.common_tags
}

resource "aws_cloudwatch_event_target" "producer_event_target" {
  rule      = aws_cloudwatch_event_rule.producer_event_trigger.name
  arn       = aws_lambda_function.producer_lambda.arn
  target_id = "ProducerTarget"
}

resource "aws_lambda_permission" "producer_lambda_permission" {
  statement_id  = local.permission_ids.eventbridge_invoke
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.producer_lambda.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.producer_event_trigger.arn
}

resource "aws_cloudwatch_metric_alarm" "producer_lambda_errors_alarm" {
  alarm_name        = local.alarm_names.producer_errors
  alarm_description = "Triggers when the producer Lambda records any errors"
  namespace         = "AWS/Lambda"
  metric_name       = "Errors"
  dimensions = {
    FunctionName = aws_lambda_function.producer_lambda.function_name
  }
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  alarm_actions       = [aws_sns_topic.lambda_alerts.arn]
  treat_missing_data  = "notBreaching"
  
  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "consumer_lambda_errors_alarm" {
  alarm_name        = local.alarm_names.consumer_errors
  alarm_description = "Triggers when the consumer Lambda records any errors"
  namespace         = "AWS/Lambda"
  metric_name       = "Errors"
  dimensions = {
    FunctionName = aws_lambda_function.consumer_lambda.function_name
  }
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  alarm_actions       = [aws_sns_topic.lambda_alerts.arn]
  treat_missing_data  = "notBreaching"
  
  tags = local.common_tags
}

data "aws_region" "current" {}

data "aws_caller_identity" "current" {}
