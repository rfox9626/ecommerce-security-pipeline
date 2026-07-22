# Data source to query all active, available availability zones in the target deployment region
data "aws_availability_zones" "available" {
  state = "available"
}

# Provisions the core Virtual Private Cloud network boundary with DNS hostnames and support enabled
resource "aws_vpc" "ecommerce_vpc_core" {
  cidr_block           = "10.1.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags                 = { Name = "ecommerce-vpc-core" }
}

# Creates the first private subnet mapped to the primary availability zone
resource "aws_subnet" "private_az1_net" {
  vpc_id            = aws_vpc.ecommerce_vpc_core.id
  cidr_block        = "10.1.1.0/24"
  tags              = { Name = "ecommerce-private-az1" }
  availability_zone = data.aws_availability_zones.available.names[0]
}

# Creates the second private subnet mapped to the secondary availability zone for high availability
resource "aws_subnet" "private_az2_net" {
  vpc_id            = aws_vpc.ecommerce_vpc_core.id
  cidr_block        = "10.1.2.0/24"
  tags              = { Name = "ecommerce-private-az2" }
  availability_zone = data.aws_availability_zones.available.names[1]
}

# Fetches the current AWS region context dynamically
data "aws_region" "current" {}

# Collects route table references associated with the core VPC
data "aws_route_tables" "rtbs" {
  vpc_id = aws_vpc.ecommerce_vpc_core.id
}

# Configures a gateway VPC endpoint for DynamoDB to route database traffic securely within the AWS network backbone
resource "aws_vpc_endpoint" "dynamodb" {
  vpc_id            = aws_vpc.ecommerce_vpc_core.id
  service_name      = "com.amazonaws.${data.aws_region.current.name}.dynamodb"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = data.aws_route_tables.rtbs.ids
}

# Provisions an interface VPC endpoint for SQS to allow private, internet-free message queue polling from subnets
resource "aws_vpc_endpoint" "sqs_endpoint" {
  vpc_id              = aws_vpc.ecommerce_vpc_core.id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.sqs"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.private_az1_net.id, aws_subnet.private_az2_net.id]
  security_group_ids  = [aws_security_group.lambda_sg_sec.id]
  private_dns_enabled = true
}
