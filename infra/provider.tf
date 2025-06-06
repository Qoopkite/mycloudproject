terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }

  backend "s3" {
    bucket         = "qoopkite-terraform-state"
    key            = "mycloudproject/terraform.tfstate"
    region         = "ap-northeast-2"
    dynamodb_table = "myproject-terraform-locks"
    encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region
}

