terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Region is fixed by the AWS Academy Learner Lab (us-east-1 only).
provider "aws" {
  region = var.aws_region
}
