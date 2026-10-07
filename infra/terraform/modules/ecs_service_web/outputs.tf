output "service_name" {
  description = "Name of the ECS web service"
  value       = aws_ecs_service.this.name
}

output "task_definition_arn" {
  description = "ARN of the web task definition"
  value       = aws_ecs_task_definition.this.arn
}

output "alb_dns_name" {
  description = "DNS name of the ALB"
  value       = aws_lb.this.dns_name
}

output "alb_arn" {
  description = "ARN of the ALB"
  value       = aws_lb.this.arn
}

output "target_group_arn" {
  description = "ARN of the ALB target group"
  value       = aws_lb_target_group.this.arn
}

output "container_definitions" {
  description = "JSON container definitions of the web task"
  value       = aws_ecs_task_definition.this.container_definitions
}
