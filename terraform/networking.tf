resource "aws_vpc" "ecommerce_vpc_core" {
  cidr_block           = "10.1.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags                 = { Name = "ecommerce-vpc-core" }
}

resource "aws_subnet" "private_az1_net" {
  vpc_id     = aws_vpc.ecommerce_vpc_core.id
  cidr_block = "10.1.1.0/24"
  tags       = { Name = "ecommerce-private-az1" }
  availability_zone = "us-east-1a"  # Explicit AZ 1
}

resource "aws_subnet" "private_az2_net" {
  vpc_id     = aws_vpc.ecommerce_vpc_core.id
  cidr_block = "10.1.2.0/24"
  tags       = { Name = "ecommerce-private-az2" }
  availability_zone = "us-east-1b"  # Explicit different AZ 2
}

data "aws_region" "current" {}

data "aws_route_tables" "rtbs" {
  vpc_id = aws_vpc.ecommerce_vpc_core.id
}

resource "aws_vpc_endpoint" "dynamodb" {
  vpc_id            = aws_vpc.ecommerce_vpc_core.id
  service_name      = "com.amazonaws.${data.aws_region.current.name}.dynamodb"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = data.aws_route_tables.rtbs.ids
}

resource "aws_vpc_endpoint" "sqs_endpoint" {
  vpc_id              = aws_vpc.ecommerce_vpc_core.id
  service_name        = "com.amazonaws.us-east-1.sqs"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.private_az1_net.id, aws_subnet.private_az2_net.id]
  security_group_ids  = [aws_security_group.lambda_sg_sec.id]
  private_dns_enabled = true
}
