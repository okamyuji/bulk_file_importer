output "service_name" {
  description = "Name of the ECS worker service"
  value       = aws_ecs_service.this.name
}

output "task_definition_arn" {
  description = "ARN of the worker task definition"
  value       = aws_ecs_task_definition.this.arn
}

output "container_definitions" {
  description = "JSON container definitions of the worker task"
  value       = aws_ecs_task_definition.this.container_definitions
}
