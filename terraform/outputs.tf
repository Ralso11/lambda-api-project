output "api_url" {
  description = "The public URL to call the quote API"
  value       = "${aws_apigatewayv2_stage.default.invoke_url}quote"
}

output "lambda_function_name" {
  description = "Name of the deployed Lambda function"
  value       = aws_lambda_function.quote_api.function_name
}

output "dashboard_url" {
  description = "URL to view the CloudWatch dashboard"
  value       = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${var.project_name}-dashboard"
}
