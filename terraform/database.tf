resource "aws_dynamodb_table" "transactions_store" {
  name         = "ecommerce-transactions-prod"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "transaction_id"

  attribute {
    name = "transaction_id"
    type = "S"
  }
}

resource "aws_elasticache_serverless_cache" "redis_store" {
  engine             = "redis"
  name               = "ecommerce-rate-limiter-cache"
  security_group_ids = [aws_security_group.redis_sg_sec.id]
  subnet_ids         = [aws_subnet.private_az1_net.id, aws_subnet.private_az2_net.id]

  cache_usage_limits {
    data_storage {
      maximum = 5
      unit    = "GB"
    }
    ecpu_per_second {
      maximum = 5000
    }
  }
}
