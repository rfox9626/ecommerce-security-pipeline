# Defines the security group regulating firewall traffic rules for the Lambda execution environments
resource "aws_security_group" "lambda_sg_sec" {
  name   = "ecommerce-lambda-security-group"
  vpc_id = aws_vpc.ecommerce_vpc_core.id

  # Permits inbound HTTPS traffic internally for SQS VPC endpoints and AWS service APIs
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    self        = true
  }

  # Permits inbound Redis traffic communication channels internally
  ingress {
    from_port   = 6379
    to_port     = 6379
    protocol    = "tcp"
    self        = true
  }

  # Allows all outbound traffic from the Lambda functions to reach external endpoints or the internet
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Defines a dedicated security group isolating the ElastiCache Redis cluster perimeter
resource "aws_security_group" "redis_sg_sec" {
  name   = "ecommerce-redis-security-group"
  vpc_id = aws_vpc.ecommerce_vpc_core.id

  # Restricts incoming Redis queries to accept traffic exclusively from the Lambda security group
  ingress {
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.lambda_sg_sec.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Explicit egress rule allowing Lambda to communicate with the Redis data store on port 6379
resource "aws_security_group_rule" "lambda_to_redis" {
  type                     = "egress"
  from_port                = 6379
  to_port                  = 6379
  protocol                 = "tcp"
  security_group_id        = aws_security_group.lambda_sg_sec.id
  source_security_group_id = aws_security_group.redis_sg_sec.id
}

# Explicit egress rule allowing Lambda to reach the SQS interface endpoint over HTTPS
resource "aws_security_group_rule" "lambda_egress_to_sqs" {
  type                     = "egress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  security_group_id        = aws_security_group.lambda_sg_sec.id
  source_security_group_id = aws_security_group.lambda_sg_sec.id
}

# General HTTPS egress rule for broader internet or external service connectivity
resource "aws_security_group_rule" "lambda_egress_https" {
  type              = "egress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.lambda_sg_sec.id
}

# Ingress rule handling secure communication back through the SQS VPC endpoint
resource "aws_security_group_rule" "sqs_endpoint_ingress_https" {
  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  security_group_id        = aws_security_group.lambda_sg_sec.id
  source_security_group_id = aws_security_group.lambda_sg_sec.id
}

# Ingress rule permitting Redis connections originating from authorized Lambda instances
resource "aws_security_group_rule" "redis_ingress_from_lambda" {
  type                     = "ingress"
  from_port                = 6379
  to_port                  = 6379
  protocol                 = "tcp"
  security_group_id        = aws_security_group.redis_sg_sec.id
  source_security_group_id = aws_security_group.lambda_sg_sec.id
}
