# Defines the IAM role that grants AWS Lambda functions the necessary permissions to execute
resource "aws_iam_role" "lambda_execution_role" {
  name = "ecommerce-lambda-execution-role"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Action = "sts:AssumeRole", Effect = "Allow", Principal = { Service = "lambda.amazonaws.com" } }]
  })
}

# Attaches the AWS managed policy allowing Lambda functions to operate inside a VPC (managing ENIs)
resource "aws_iam_role_policy_attachment" "lambda_vpc_access" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

# Attaches full DynamoDB access to the Lambda execution role
resource "aws_iam_role_policy_attachment" "lambda_dynamodb_access" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess"
}

# Attaches full SQS access to the Lambda execution role
resource "aws_iam_role_policy_attachment" "lambda_sqs_access" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSQSFullAccess"
}

# Provides a custom inline policy restricting DynamoDB write actions strictly to our transactions table ARN
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

# Creates an ECR repository to store the API ingress container image
resource "aws_ecr_repository" "api_repo" {
  name = "ecommerce-lambda-v2"
}

# Creates an ECR repository to store the SQS queue worker container image
resource "aws_ecr_repository" "handler_repo" {
  name = "sqs-redis-handler-v2"
}

# Provisions the API ingress Lambda function using a container image package type
resource "aws_lambda_function" "api_ingress" {
  function_name = "ecommerce-ingest-api"
  role          = aws_iam_role.lambda_execution_role.arn
  package_type  = "Image"
  image_uri     = "${aws_ecr_repository.api_repo.repository_url}:latest"
  timeout       = 30

  # Connects the Lambda to private subnets inside the VPC via specific security groups
  vpc_config {
    subnet_ids         = [aws_subnet.private_az1_net.id, aws_subnet.private_az2_net.id]
    security_group_ids = [aws_security_group.lambda_sg_sec.id]
  }

  # Passes runtime environment variables for downstream Redis and SQS integrations
  environment {
    variables = {
      REDIS_ENDPOINT = "${aws_elasticache_serverless_cache.redis_store.endpoint[0].address}:6379"
      SQS_QUEUE_URL  = aws_sqs_queue.order_queue.url
    }
  }
}

# Provisions the background queue worker Lambda function to process messages from SQS
resource "aws_lambda_function" "queue_worker" {
  function_name = "ecommerce-sqs-redis-worker"
  role          = aws_iam_role.lambda_execution_role.arn
  package_type  = "Image"
  image_uri     = "${aws_ecr_repository.handler_repo.repository_url}:latest"
  timeout       = 30

  # Configures private networking for secure internal data processing
  vpc_config {
    subnet_ids         = [aws_subnet.private_az1_net.id, aws_subnet.private_az2_net.id]
    security_group_ids = [aws_security_group.lambda_sg_sec.id]
  }

  # Configures environment parameters for Redis connection pooling inside the worker
  environment {
    variables = {
      REDIS_HOST = aws_elasticache_serverless_cache.redis_store.endpoint[0].address
      REDIS_PORT = 6379
    }
  }
}

# Maps the SQS queue as an event source trigger for the queue worker Lambda function with a batch size of 1
resource "aws_lambda_event_source_mapping" "sqs_to_lambda" {
  event_source_arn = aws_sqs_queue.order_queue.arn
  function_name    = aws_lambda_function.queue_worker.arn
  batch_size       = 1
}

# Defines an explicit policy allowing message publication and attribute retrieval on the SQS order queue
resource "aws_iam_policy" "lambda_sqs_policy" {
  name = "ecommerce-lambda-sqs-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["sqs:SendMessage", "sqs:GetQueueAttributes"]
        Resource = aws_sqs_queue.order_queue.arn
      }
    ]
  })
}
