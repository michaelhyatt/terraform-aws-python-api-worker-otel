provider "aws" {
  region = var.aws_region
}

module "python-producer-lambda-function" {
  source = "terraform-aws-modules/lambda/aws"

  function_name = format("%s-producer", var.function_name)
  handler       = "handler.producer"
  runtime       = "python3.8"

  create_package         = true

  source_path = "../src"

  timeout = 30

  layers = compact([
    lookup(local.sdk_layer_arns, var.aws_region, "invalid")
  ])

  environment_variables = {
    AWS_LAMBDA_EXEC_WRAPPER: "/var/task/otel-instrument.py"
    ELASTIC_OTLP_ENDPOINT: var.elastic_otlp_endpoint
    ELASTIC_OTLP_TOKEN: var.elastic_otlp_token
    OPENTELEMETRY_COLLECTOR_CONFIG_FILE: "/var/task/opentelemetry-collector.yaml"
    OTEL_PROPAGATORS: "tracecontext"
    CONSUMER_API: module.consumer-api-gateway.api_gateway_url
  }

  tracing_mode = "PassThrough" // ensure xray doesn't modify the trace context. See "api-gateway" enable_xray_tracing below

}

module "python-consumer-lambda-function" {
  source = "terraform-aws-modules/lambda/aws"

  function_name = format("%s-consumer", var.function_name)
  handler       = "handler.consumer"
  runtime       = "python3.8"

  create_package         = true

  timeout = 20

  source_path = "../src"

  layers = compact([
    lookup(local.sdk_layer_arns, var.aws_region, "invalid")
  ])

  environment_variables = {
    AWS_LAMBDA_EXEC_WRAPPER = "/var/task/otel-instrument.py"
    ELASTIC_OTLP_ENDPOINT: var.elastic_otlp_endpoint
    ELASTIC_OTLP_TOKEN: var.elastic_otlp_token
    OPENTELEMETRY_COLLECTOR_CONFIG_FILE: "/var/task/opentelemetry-collector.yaml"
    OTEL_PROPAGATORS: "tracecontext"
  }

  tracing_mode = "PassThrough" // ensure xray doesn't modify the trace context. See "api-gateway" enable_xray_tracing below

}

module "consumer-api-gateway" {
  source = "../utils/terraform/api-gateway-proxy"

  name                = format("%s-APIGW", var.function_name)
  function_name       = module.python-consumer-lambda-function.lambda_function_name
  function_invoke_arn = module.python-consumer-lambda-function.lambda_function_invoke_arn
  enable_xray_tracing = false // ensure xray doesn't modify the trace context. See AWS Lambda Function attribute `tracing_mode` above

}

module "producer-api-gateway" {
  source = "../utils/terraform/api-gateway-proxy"

  name                = format("%s-APIGW", var.function_name)
  function_name       = module.python-producer-lambda-function.lambda_function_name
  function_invoke_arn = module.python-producer-lambda-function.lambda_function_invoke_arn
  enable_xray_tracing = false // ensure xray doesn't modify the trace context. See AWS Lambda Function attribute `tracing_mode` above

}