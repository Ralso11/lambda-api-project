output "api_url" {
  description = "The public URL to call the quote API"
  value       = "${aws_apigatewayv2_stage.default.invoke_url}quote"
}

output "lambda_function_name" {
  description = "Name of the deployed Lambda function"
  value       = aws_lambda_function.quote_api.function_name
}
