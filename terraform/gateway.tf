# Creates a modern lightweight HTTP API Gateway instance for high-performance routing
resource "aws_apigatewayv2_api" "http_api" {
  name          = "ecommerce-http-api"
  protocol_type = "HTTP"
}

# Binds the HTTP API Gateway directly to the API Ingress Lambda function via an AWS Proxy integration
resource "aws_apigatewayv2_integration" "api_integration" {
  api_id           = aws_apigatewayv2_api.http_api.id
  integration_type = "AWS_PROXY"
  integration_uri  = aws_lambda_function.api_ingress.invoke_arn
}

# Defines an explicit HTTP route mapping POST requests on /ingest to the backend Lambda integration
resource "aws_apigatewayv2_route" "default_route" {
  api_id    = aws_apigatewayv2_api.http_api.id
  route_key = "POST /ingest"
  target    = "integrations/${aws_apigatewayv2_integration.api_integration.id}"
}

# Grants API Gateway explicit permission to invoke the API Ingress Lambda function
resource "aws_lambda_permission" "api_gw_permission" {
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.api_ingress.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.http_api.execution_arn}/*/*"
}

# Creates a default stage configured for automatic deployment of changes
resource "aws_apigatewayv2_stage" "default_stage" {
  api_id      = aws_apigatewayv2_api.http_api.id
  name        = "$default"
  auto_deploy = true
}
