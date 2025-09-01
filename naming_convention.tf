# =============================================================================
# SMART NAMING CONVENTION FOR AWS CONTROL TOWER CONFIG CUSTOMIZATION
# =============================================================================
# This file provides a standardized naming convention system specifically 
# designed for your AWS Control Tower configuration customization project.

# =============================================================================
# SMART NAMING LOCALS
# =============================================================================

locals {
  # Current region and abbreviated form
  current_region = data.aws_region.current.region
  region_abbreviations = {
    "us-east-1"      = "use1"
    "us-east-2"      = "use2"
    "us-west-1"      = "usw1"
    "us-west-2"      = "usw2"
    "eu-west-1"      = "euw1"
    "eu-west-2"      = "euw2"
    "eu-central-1"   = "euc1"
    "ap-southeast-1" = "apse1"
    "ap-southeast-2" = "apse2"
    "ap-northeast-1" = "apne1"
    "ca-central-1"   = "cac1"
  }
  
  region_short = var.include_region_in_names ? lookup(local.region_abbreviations, local.current_region, substr(local.current_region, 0, 4)) : ""
  
  # Base naming components
  name_components = compact([
    var.owner_short,
    var.naming_prefix,
    var.environment,
    local.region_short
  ])
  
  base_name = join("-", local.name_components)
  
  # =============================================================================
  # RESOURCE-SPECIFIC NAMING PATTERNS
  # =============================================================================
  
  # Lambda function names (AWS limits: 64 chars, no special chars except hyphens)
  lambda_names = {
    producer = "${local.base_name}-producer"
    consumer = "${local.base_name}-consumer"
  }
  
  # IAM role names (AWS limits: 64 chars)
  iam_role_names = {
    producer_execution = "${local.base_name}-producer-role"
    consumer_execution = "${local.base_name}-consumer-role"
  }
  
  # IAM policy names
  iam_policy_names = {
    producer = "${local.base_name}-producer-policy"
    consumer = "${local.base_name}-consumer-policy"
  }
  
  # S3 related names (must be globally unique and DNS compliant)
  s3_names = {
    object_key = "${var.owner_short}/${var.naming_prefix}/${var.environment}/lambda_functions.zip"
  }
  
  # SNS topic names
  sns_names = {
    lambda_alerts = "${local.base_name}-lambda-alerts"
  }
  
  # SQS queue names
  sqs_names = {
    config_recorder = "${local.base_name}-config-recorder-queue"
  }
  
  # CloudWatch Log Group names (following AWS Lambda convention)
  cloudwatch_names = {
    lambda_logs = "/aws/lambda/${local.base_name}"
    log_group_tag = "${local.base_name}-logs"
  }
  
  # CloudWatch Event Rule names
  event_rule_names = {
    producer_trigger = "${local.base_name}-producer-trigger"
  }
  
  # CloudWatch Alarm names
  alarm_names = {
    producer_errors = "${local.base_name}-producer-errors"
    consumer_errors = "${local.base_name}-consumer-errors"
  }
  
  # Lambda permission statement IDs
  permission_ids = {
    eventbridge_invoke = "AllowEventBridgeInvoke"
  }
  
  # =============================================================================
  # TAGGING STRATEGY
  # =============================================================================
  
  common_tags = merge(var.default_tags, {
    Name        = local.base_name
    Environment = var.environment
    Owner       = var.owner_short
    Project     = var.naming_prefix
    Region      = local.current_region
    ManagedBy   = "terraform"
  })
  
  # Resource-specific tag generators
  resource_tags = {
    lambda_producer = merge(local.common_tags, {
      Name        = local.lambda_names.producer
      Component   = "producer"
      ResourceType = "lambda"
    })
    
    lambda_consumer = merge(local.common_tags, {
      Name        = local.lambda_names.consumer
      Component   = "consumer"
      ResourceType = "lambda"
    })
    
    sns_alerts = merge(local.common_tags, {
      Name        = local.sns_names.lambda_alerts
      Component   = "monitoring"
      ResourceType = "sns"
    })
    
    sqs_queue = merge(local.common_tags, {
      Name        = local.sqs_names.config_recorder
      Component   = "messaging"
      ResourceType = "sqs"
    })
    
    cloudwatch_logs = merge(local.common_tags, {
      Name        = local.cloudwatch_names.log_group_tag
      Component   = "logging"
      ResourceType = "cloudwatch"
    })
  }
}

# =============================================================================
# HELPER FUNCTIONS (via outputs for reusability)
# =============================================================================

# Example of the generated base name with current tfvars
output "generated_base_name_example" {
  description = "Example: with owner_short='myorg', prefix='ct-config', env='prod', region='ap-southeast-2'"
  value = "Base name would be: ${local.base_name}"
}