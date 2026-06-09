terraform {
  required_version = "~> 1.7"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket         = "self-healing-tf-state-625782202054"
    key            = "self-healing-infra/terraform.tfstate"
    region         = "ap-south-1"
    dynamodb_table = "terraform-state-lock"
    encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "self-healing-infra"
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

module "dynamodb" {
  source = "./modules/dynamodb"

  table_name = "self-healing-incidents"
}

module "lambdas" {
  source = "./modules/lambdas"

  environment                   = var.environment
  aws_region                    = var.aws_region
  dynamodb_table_arn            = module.dynamodb.table_arn
  ses_sender_email              = var.ses_sender_email
  ses_recipient_email           = var.ses_recipient_email
  gemini_model_id               = var.gemini_model_id
  approval_token_secret         = var.approval_token_secret
  approval_token_expiry_minutes = var.approval_token_expiry_minutes
  api_gateway_base_url          = "https://r0hzp2rsva.execute-api.ap-south-1.amazonaws.com/v1"
}

module "ssm_documents" {
  source = "./modules/ssm_documents"
}

module "step_functions" {
  source = "./modules/step_functions"

  environment                    = var.environment
  diagnostic_lambda_arn          = module.lambdas.diagnostic_lambda_arn
  send_approval_email_lambda_arn = module.lambdas.send_approval_email_lambda_arn
  execute_runbook_lambda_arn     = module.lambdas.execute_runbook_lambda_arn
  send_result_email_lambda_arn   = module.lambdas.send_result_email_lambda_arn
}

module "api_gateway" {
  source = "./modules/api_gateway"

  environment                   = var.environment
  aws_region                    = var.aws_region
  approval_callback_lambda_arn  = module.lambdas.approval_callback_lambda_arn
  approval_callback_lambda_name = module.lambdas.approval_callback_lambda_name
}

module "cloudwatch" {
  source = "./modules/cloudwatch"
}

module "eventbridge" {
  source = "./modules/eventbridge"

  environment        = var.environment
  step_functions_arn = module.step_functions.state_machine_arn
}

module "github_oidc" {
  source = "./modules/github_oidc"

  github_org  = "Achinthya18"
  github_repo = "SelfHeal"
  environment = var.environment
}

module "dashboard" {
  source = "./modules/dashboard"

  environment           = var.environment
  aws_region            = var.aws_region
  state_machine_arn     = module.step_functions.state_machine_arn
  lambda_function_names = module.lambdas.function_names
  dynamodb_table_name   = module.dynamodb.table_name
  api_gateway_name      = "self-healing-approval-${var.environment}"
  api_gateway_stage     = "v1"
  alarm_names           = module.cloudwatch.alarm_names
}
