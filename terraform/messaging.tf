resource "aws_sqs_queue" "order_queue" {
  name = "ecommerce-orders-queue"
}
