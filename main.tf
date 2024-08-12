# S3 bucket to store Lambda function code
resource "aws_s3_bucket" "lambda_bucket" {
  bucket = "assumable-role-checker-bucket"
  force_destroy = true
}

# S3 bucket to store CloudTrail logs
resource "aws_s3_bucket" "trail_bucket" {
  bucket = "my-cloudtrail-logs-bucket-352652"
  acl    = "private"
  force_destroy = true
}

# S3 bucket policy to allow CloudTrail to write logs
resource "aws_s3_bucket_policy" "trail_bucket_policy" {
  bucket = aws_s3_bucket.trail_bucket.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        },
        Action = "s3:PutObject",
        Resource = "${aws_s3_bucket.trail_bucket.arn}/*"
      },
      {
        Effect = "Allow",
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        },
        Action = "s3:GetBucketAcl",
        Resource = aws_s3_bucket.trail_bucket.arn
      }
    ]
  })
}

# IAM Role for Lambda Function
resource "aws_iam_role" "lambda_role" {
  name = "assumable-role-checker"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_s3_bucket_object" "lambda_function_zip" {
  bucket = aws_s3_bucket.lambda_bucket.bucket
  key    = "lambda_function.zip"
  source = "lambda_function.zip" # Path to your local zip file
  etag   = filemd5("lambda_function.zip") # Use filemd5 for consistency
}

# Attach Policies to Lambda IAM Role
resource "aws_iam_role_policy_attachment" "lambda_policy" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "dynamodb_policy" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess"
}

resource "aws_iam_role_policy_attachment" "sns_policy" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSNSFullAccess"
}

# DynamoDB Table to Store Externally Assumable Roles Data
resource "aws_dynamodb_table" "role_mappings" {
  name         = "ExternallyAssumableRoles"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "RoleName"
  range_key    = "Principal" # Adding Principal as the sort key

  attribute {
    name = "RoleName"
    type = "S"
  }

  attribute {
    name = "Principal"
    type = "S"
  }
}

# SNS Topic for Alerting
resource "aws_sns_topic" "alerts_topic" {
  name = "ExternallyAssumableRolesAlerts"
}

resource "aws_sns_topic_subscription" "aws_sns_topic_subscription" {
  topic_arn = aws_sns_topic.alerts_topic.arn
  protocol = "email"
  endpoint = "ma2588780@gmail.com"
}

# Get AWS Account ID
data "aws_caller_identity" "current" {}

# Lambda Function to Query Externally Assumable Roles
resource "aws_lambda_function" "role_checker" {
  function_name    = "AssumableRoleChecker"
  s3_bucket        = aws_s3_bucket.lambda_bucket.bucket
  s3_key           = "lambda_function.zip" # Upload your Lambda zip file to S3
  role             = aws_iam_role.lambda_role.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.9"
  source_code_hash = filebase64sha256("lambda_function.zip")
  timeout          = 300

  environment {
    variables = {
      DYNAMODB_TABLE_NAME = aws_dynamodb_table.role_mappings.name
      SNS_TOPIC_ARN       = aws_sns_topic.alerts_topic.arn
      ACCOUNT_ID          = data.aws_caller_identity.current.account_id
    }
  }
}

# CloudWatch Event Rule to Trigger Lambda Function on IAM Role Creation
resource "aws_cloudwatch_event_rule" "role_creation_rule" {
  name        = "RoleCreationRule"
  description = "Trigger Lambda on IAM Role Creation"
  event_pattern = jsonencode({
    source = ["aws.iam"],
    detail_type = ["AWS API Call via CloudTrail"],
    detail = {
      eventSource = ["iam.amazonaws.com"],
      eventName   = ["CreateRole"]
    }
  })
}

# CloudWatch Event Target to Link Event Rule to Lambda Function
resource "aws_cloudwatch_event_target" "role_creation_target" {
  rule = aws_cloudwatch_event_rule.role_creation_rule.name
  arn  = aws_lambda_function.role_checker.arn
}

# Permission to Allow CloudWatch Events to Invoke Lambda Function
resource "aws_lambda_permission" "allow_cloudwatch_events" {
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.role_checker.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.role_creation_rule.arn
}

# CloudTrail for logging IAM events
resource "aws_cloudtrail" "main" {
  name                          = "my-cloudtrail"
  s3_bucket_name                = aws_s3_bucket.trail_bucket.bucket
  include_global_service_events = true
  enable_logging                = true

  event_selector {
    read_write_type            = "All"
    include_management_events = true
  }
}

# Output the DynamoDB Table Name for Reference
output "dynamodb_table_name" {
  value = aws_dynamodb_table.role_mappings.name
}

# Output the SNS Topic ARN for Alerting Reference
output "sns_topic_arn" {
  value = aws_sns_topic.alerts_topic.arn
}
