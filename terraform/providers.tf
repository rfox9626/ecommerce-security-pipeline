# Sets base constraints for the Terraform execution binary and required external providers
terraform {
  required_version = ">= 1.0.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Configures the core AWS provider region to Ohio (us-east-2)
provider "aws" {
  region = "us-east-2"
}
