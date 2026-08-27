# Package the Lambda code into a zip file automatically
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/../lambda/handler.py"
  output_path = "${path.module}/lambda.zip"
}

# The IAM role the Lambda function will run as
resource "aws_iam_role" "lambda_exec" {
  name = "${var.project_name}-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

# Grants just enough permission to write logs to CloudWatch
resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# The Lambda function itself
resource "aws_lambda_function" "quote_api" {
  function_name    = "${var.project_name}-${var.environment}"
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  handler          = "handler.handler"
  runtime          = "python3.12"
  role             = aws_iam_role.lambda_exec.arn
}

# The API Gateway that exposes the Lambda function over HTTP
resource "aws_apigatewayv2_api" "quote_api" {
  name          = "${var.project_name}-${var.environment}-api"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_integration" "lambda" {
  api_id                 = aws_apigatewayv2_api.quote_api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.quote_api.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "get_quote" {
  api_id    = aws_apigatewayv2_api.quote_api.id
  route_key = "GET /quote"
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.quote_api.id
  name        = "$default"
  auto_deploy = true
}

# Allows API Gateway to actually invoke the Lambda function
resource "aws_lambda_permission" "api_gw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.quote_api.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.quote_api.execution_arn}/*/*"
}
