#create dynamodb table
resource "aws_dynamodb_table" "task_table" {
  name           = "task-table"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "task_id"

  attribute {
    name = "task_id"
    type = "S"
  }
  ttl {
    attribute_name = "expiry"
    enabled        = true
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

#zip the python file
data "archive_file" "add_task_zip" {
  type        = "zip"
  source_file = "${path.module}/src/add_task.py"
  output_path = "${path.module}/src/add_task.zip"
}

data "archive_file" "check_reminders_zip" {
  type        = "zip"
  source_file = "${path.module}/src/check_reminder.py"
  output_path = "${path.module}/src/check_reminder.zip"
}

#defining IAM role 
resource "aws_iam_role" "lambda_role" {
  name = "lambda-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      },
    ]
  })
}

#attach policy to the role
resource "aws_iam_role_policy_attachment" "lambda_policy_attachment" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}

#define IAM policy for lambda role
resource "aws_iam_policy" "lambda_policy" {
  name        = "lambda-execution-policy"
  description = "IAM policy for Lambda execution role"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "dynamodb:PutItem",
          "dynamodb:Scan",
          "dynamodb:DeleteItem"
        ]
        Effect   = "Allow",
        Resource = aws_dynamodb_table.task_table.arn
      },
      {
        Action = [
          "sns:Publish"
        ]
        Effect   = "Allow",
        Resource = aws_sns_topic.task_notification.arn
      },
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Effect   = "Allow",
        Resource = "*"
      }
    ]
  })
}

#add_task lambda function
resource "aws_lambda_function" "add_task_lambda" {
  function_name = "add-task-lambda"
  role          = aws_iam_role.lambda_role.arn
  handler       = "add_task.lambda_handler"
  runtime       = "python3.12"
  filename      = data.archive_file.add_task_zip.output_path
  source_code_hash = data.archive_file.add_task_zip.output_base64sha256

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.task_table.name
      SNS_TOPIC_ARN = aws_sns_topic.task_notification.arn
    }
  }
}

#check_reminder lambda function
resource "aws_lambda_function" "check_reminder_lambda" {
  function_name = "check-reminder-lambda"
  role          = aws_iam_role.lambda_role.arn
  handler       = "check_reminder.lambda_handler"
  runtime       = "python3.12"
  filename      = data.archive_file.check_reminders_zip.output_path
  source_code_hash = data.archive_file.check_reminders_zip.output_base64sha256

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.task_table.name
      SNS_TOPIC_ARN = aws_sns_topic.task_notification.arn
    }
  }
}

#create http api gateway
resource "aws_apigatewayv2_api" "task_api" {
  name          = "task-api"
  protocol_type = "HTTP"
  cors_configuration {
    allow_origins = ["*"]
    allow_methods = ["GET", "POST", "DELETE", "OPTIONS"]
    allow_headers = ["*"]
  }
}

#connect api gateway to add_task lambda function
resource "aws_apigatewayv2_integration" "task_integration" {
  api_id           = aws_apigatewayv2_api.task_api.id
  integration_type = "AWS_PROXY"
  integration_uri  = aws_lambda_function.add_task_lambda.invoke_arn
  payload_format_version = "2.0"
  integration_method = "POST"
}

#defining URL route
resource "aws_apigatewayv2_route" "add_task_route" {
  api_id    = aws_apigatewayv2_api.task_api.id
  route_key = "POST /tasks"
  target    = "integrations/${aws_apigatewayv2_integration.task_integration.id}"
}

#route to GET tasks
resource "aws_apigatewayv2_route" "get_tasks_route" {
  api_id    = aws_apigatewayv2_api.task_api.id
  route_key = "GET /tasks"
  target    = "integrations/${aws_apigatewayv2_integration.task_integration.id}"
}

#route to delete task
resource "aws_apigatewayv2_route" "delete_task_route" {
  api_id    = aws_apigatewayv2_api.task_api.id
  route_key = "DELETE /tasks/{task_id}"
  target    = "integrations/${aws_apigatewayv2_integration.task_integration.id}"
}

#deploying the API
resource "aws_apigatewayv2_stage" "task_api_stage" {
  api_id      = aws_apigatewayv2_api.task_api.id
  name        = "$default"
  auto_deploy = true

  #bot protection values
  default_route_settings {
    throttling_burst_limit = 10 #max request
    throttling_rate_limit  = 5 #max per second
  }
}

#grant permission to API Gateway to invoke the Lambda function
resource "aws_lambda_permission" "api_gateway_permission" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.add_task_lambda.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.task_api.execution_arn}/*/*"
}

#output endpoint URL for the API
output "api_endpoint" {
  value = "${aws_apigatewayv2_api.task_api.api_endpoint}/tasks"
}

#create s3 bucket 
resource "aws_s3_bucket" "task_bucket" {
  bucket = "task-bucket-ashwath"
}

#give public access to the bucket
resource "aws_s3_bucket_public_access_block" "task_bucket_public_access" {
  bucket = aws_s3_bucket.task_bucket.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

#adding read only policy to bucket
resource "aws_s3_bucket_policy" "task_bucket_policy" {
  bucket = aws_s3_bucket.task_bucket.id
  depends_on = [aws_s3_bucket_public_access_block.task_bucket_public_access]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = "*"
        Action = [
          "s3:GetObject"
        ]
        Resource = "${aws_s3_bucket.task_bucket.arn}/*"
      }
    ]
  })
}

#static web hosting 
resource "aws_s3_bucket_website_configuration" "task_bucket_website" {
  bucket = aws_s3_bucket.task_bucket.id

  index_document {
    suffix = "index.html"
  }

  error_document {
    key = "error.html"
  }
}

#upload index.html to s3 bucket
resource "aws_s3_bucket_object" "index_html" {
  bucket = aws_s3_bucket.task_bucket.id
  key    = "index.html"
  source = "${path.module}/index.html"
  content_type = "text/html"
  etag = filemd5("${path.module}/index.html") #updates if i change index.html

}

output "s3_bucket_website_url" {
  value = aws_s3_bucket_website_configuration.task_bucket_website.website_endpoint
}

#creating eventbridge rule to trigger check_reminder lambda function every 7 days indian time
resource "aws_cloudwatch_event_rule" "check_reminder_rule" {
  name                = "check-reminder-rule"
  schedule_expression = "cron(30 2 * * ? *)"
}

#connect the eventbridge rule to the check_reminder lambda function
resource "aws_cloudwatch_event_target" "check_reminder_target" {
  rule      = aws_cloudwatch_event_rule.check_reminder_rule.name
  target_id = "check-reminder-lambda"
  arn       = aws_lambda_function.check_reminder_lambda.arn
}

#permission for eventbridge to invoke the check_reminder lambda function
resource "aws_lambda_permission" "eventbridge_permission" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.check_reminder_lambda.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.check_reminder_rule.arn
}

#cloudfront 
resource "aws_cloudfront_distribution" "secure_frontend_distribution" {
  origin {
    domain_name = aws_s3_bucket.task_bucket.bucket_regional_domain_name
    origin_id   = "s3-task-bucket"
    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  enabled             = true
  default_root_object = "index.html"

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "s3-task-bucket"

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
  }

  

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}

output url {
  value = aws_cloudfront_distribution.secure_frontend_distribution.domain_name
}