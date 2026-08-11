#create dynamodb table
resource "aws_dynamodb_table" "task_table" {
  name           = "task-table"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "task_id"

  attribute {
    name = "task_id"
    type = "S"
  }
}

#sns for email notification
  resource "aws_sns_topic" "task_notification" {
    name = "task-notification-topic"
  }

#sns subscription for email notification
  resource "aws_sns_topic_subscription" "task_notification_email" {
    topic_arn = aws_sns_topic.task_notification.arn
    protocol  = "email"
    endpoint  = "ashwathc23@gmail.com"
  } 
    output "sns_topic_arn" {
      value = aws_sns_topic.task_notification.arn
    }

    output "dynamodb_table_name" {
      value = aws_dynamodb_table.task_table.name
    }   
