# Provisions a standard Amazon SQS queue to buffer incoming transaction bursts asynchronously
resource "aws_sqs_queue" "order_queue" {
  name = "ecommerce-orders-queue"
}
