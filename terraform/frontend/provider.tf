terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  alias  = "default"
  region = var.aws_region
}

# CloudFront distributions only accept ACM certs from us-west-1
provider "aws" {
  alias  = "us_east_1"
  region = "us-west-1"
}
