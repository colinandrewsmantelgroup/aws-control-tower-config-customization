variable "excluded_accounts" {
  description = "Excluded Accounts list."
  type        = string
  default     = "['111111111111', '222222222222', '333333333333']"
}

variable "source_s3_bucket" {
  description = "S3 bucket containing the Lambda deployment packages."
  type        = string
  default     = "marketplace-sa-resources"
}

variable "lambda_s3_key" {
  description = "S3 key for Lambda deployment package containing all Python files."
  type        = string
  default     = "ct-blogs-content/lambda_functions.zip"
}

variable "config_recorder_strategy" {
  description = "Config Recorder Strategy"
  type        = string
  default     = "EXCLUSION"
}

variable "config_recorder_excluded_resource_types" {
  description = "List of all resource types to be excluded from Config Recorder if you pick EXCLUSION strategy"
  type        = string
  default     = "AWS::HealthLake::FHIRDatastore,AWS::Pinpoint::Segment,AWS::Pinpoint::ApplicationSettings"
}

variable "config_recorder_included_resource_types" {
  description = "List of all resource types to be included in Config Recorder if you pick INCLUSION strategy"
  type        = string
  default     = "AWS::S3::Bucket,AWS::CloudTrail::Trail"
}

variable "config_recorder_daily_resource_types" {
  description = "List of all resource types to be set to a daily cadence"
  type        = string
  default     = "AWS::AutoScaling::AutoScalingGroup,AWS::AutoScaling::LaunchConfiguration"
}

variable "config_recorder_daily_global_resource_types" {
  description = "List of Global resource types to be set to a daily cadence in the AWS Control Tower home region."
  type        = string
  default     = "AWS::IAM::Policy,AWS::IAM::User,AWS::IAM::Role,AWS::IAM::Group"
}

variable "config_recorder_default_recording_frequency" {
  description = "Default Frequency of recording configuration changes."
  type        = string
  default     = "CONTINUOUS"
}

# Provider Configuration Variables
variable "aws_region" {
  description = "AWS region for the provider"
  type        = string
  default     = "us-east-1"
}

variable "assume_role_arn" {
  description = "ARN of the role to assume for AWS provider authentication"
  type        = string
  default     = null
}

variable "assume_role_session_name" {
  description = "Session name for the assume role session"
  type        = string
  default     = "terraform-session"
}

variable "default_tags" {
  description = "Default tags to apply to all resources"
  type        = map(string)
  default = {
    project = "aws-control-tower-config"
    domain  = "cloud"
    repo    = "public"
  }
}

variable "alert_email_address" {
  description = "Email address to receive Lambda failure alerts"
  type        = string
  default     = ""
}

# =============================================================================
# NAMING CONVENTION VARIABLES
# =============================================================================

variable "naming_prefix" {
  description = "Primary prefix for all resource names"
  type        = string
  default     = "ct-config"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.naming_prefix))
    error_message = "Naming prefix must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "environment" {
  description = "Environment identifier (dev, staging, prod, etc.)"
  type        = string
  default     = "prod"
  
  validation {
    condition     = contains(["dev", "test", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, test, staging, prod."
  }
}

variable "owner_short" {
  description = "Short identifier for the owner/organization"
  type        = string
  default     = "myorg"
  
  validation {
    condition     = can(regex("^[a-z0-9]+$", var.owner_short))
    error_message = "Owner short must contain only lowercase letters and numbers."
  }
}

variable "include_region_in_names" {
  description = "Whether to include region abbreviation in resource names"
  type        = bool
  default     = true
}
