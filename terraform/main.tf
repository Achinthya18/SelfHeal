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

  environment = var.environment
  table_name  = "self-healing-incidents"
}

module "lambdas" {
  source = "./modules/lambdas"

  environment                   = var.environment
  aws_region                    = var.aws_region
  dynamodb_table_arn            = module.dynamodb.table_arn
  ses_sender_email              = var.ses_sender_email
  approval_token_expiry_minutes = var.approval_token_expiry_minutes
}
