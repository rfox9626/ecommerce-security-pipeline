resource "aws_security_group" "lambda_sg_sec" {
  name   = "ecommerce-lambda-security-group"
  vpc_id = aws_vpc.ecommerce_vpc_core.id

  # Allow inbound HTTPS for the SQS VPC Endpoint (and other AWS APIs)
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    self        = true
  }

  # Allow inbound Redis traffic for ElastiCache
  ingress {
    from_port   = 6379
    to_port     = 6379
    protocol    = "tcp"
    self        = true
  }

  # Allow all outbound traffic to talk to endpoints and the internet/AWS services
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "redis_sg_sec" {
  name   = "ecommerce-redis-security-group"
  vpc_id = aws_vpc.ecommerce_vpc_core.id

  # Allow inbound Redis traffic from our Lambda functions
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

resource "aws_security_group_rule" "lambda_to_redis" {
  type                     = "egress"
  from_port                = 6379
  to_port                  = 6379
  protocol                 = "tcp"
  security_group_id        = aws_security_group.lambda_sg_sec.id
  source_security_group_id = aws_security_group.redis_sg_sec.id
}

resource "aws_security_group_rule" "lambda_egress_to_sqs" {
  type                     = "egress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  security_group_id        = aws_security_group.lambda_sg_sec.id
  source_security_group_id = aws_security_group.lambda_sg_sec.id
}

resource "aws_security_group_rule" "lambda_egress_https" {
  type              = "egress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.lambda_sg_sec.id
}

resource "aws_security_group_rule" "sqs_endpoint_ingress_https" {
  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  security_group_id        = aws_security_group.lambda_sg_sec.id
  source_security_group_id = aws_security_group.lambda_sg_sec.id
}

resource "aws_security_group_rule" "redis_ingress_from_lambda" {
  type                     = "ingress"
  from_port                = 6379
  to_port                  = 6379
  protocol                 = "tcp"
  security_group_id        = aws_security_group.redis_sg_sec.id
  source_security_group_id = aws_security_group.lambda_sg_sec.id
}
