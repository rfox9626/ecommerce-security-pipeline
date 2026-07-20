resource "aws_iam_role" "lambda_execution_role" {
  name = "ecommerce-lambda-execution-role"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Action = "sts:AssumeRole", Effect = "Allow", Principal = { Service = "lambda.amazonaws.com" } }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_vpc_access" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_iam_role_policy_attachment" "lambda_dynamodb_access" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess"
}

resource "aws_iam_role_policy_attachment" "lambda_sqs_access" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSQSFullAccess"
}

resource "aws_iam_role_policy" "lambda_dynamodb_policy" {
  name = "lambda-dynamodb-custom-policy"
  role = aws_iam_role.lambda_execution_role.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["dynamodb:PutItem", "dynamodb:UpdateItem"]
      Resource = aws_dynamodb_table.transactions_store.arn
    }]
  })
}

data "aws_ecr_repository" "api_repo" {
  name = "ecommerce-lambda-v2"
}

data "aws_ecr_repository" "handler_repo" {
  name = "sqs-redis-handler-v2"
}

resource "aws_lambda_function" "api_ingress" {
  function_name = "ecommerce-ingest-api"
  role          = aws_iam_role.lambda_execution_role.arn
  package_type  = "Image"
  image_uri     = "${data.aws_ecr_repository.api_repo.repository_url}:latest"
  timeout       = 30

  vpc_config {
    subnet_ids         = [aws_subnet.private_az1_net.id, aws_subnet.private_az2_net.id]
    security_group_ids = [aws_security_group.lambda_sg_sec.id]
  }

  environment {
    variables = {
      REDIS_ENDPOINT = "${aws_elasticache_serverless_cache.redis_store.endpoint[0].address}:6379"
      SQS_QUEUE_URL  = aws_sqs_queue.order_queue.url
    }
  }
}

resource "aws_lambda_function" "queue_worker" {
  function_name = "ecommerce-sqs-redis-worker"
  role          = aws_iam_role.lambda_execution_role.arn
  package_type  = "Image"
  image_uri     = "${data.aws_ecr_repository.handler_repo.repository_url}:latest"

  vpc_config {
    subnet_ids         = [aws_subnet.private_az1_net.id, aws_subnet.private_az2_net.id]
    security_group_ids = [aws_security_group.lambda_sg_sec.id]
  }

  environment {
    variables = {
      REDIS_HOST = aws_elasticache_serverless_cache.redis_store.endpoint[0].address
    }
  }
}

resource "aws_lambda_event_source_mapping" "sqs_to_lambda" {
  event_source_arn = aws_sqs_queue.order_queue.arn
  function_name    = aws_lambda_function.queue_worker.arn
  batch_size       = 1
}
