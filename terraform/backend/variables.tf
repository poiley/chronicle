variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-west-1"
}

variable "environment" {
  description = "Deployment environment (used for naming)"
  type        = string
  default     = "prod"
}

variable "bucket_name" {
  description = "S3 bucket to store completed recordings"
  type        = string
  default     = "chronicle-recordings-prod"
}

variable "ecr_repo_name" {
  description = "Name of the ECR repository for the recorder image"
  type        = string
  default     = "chronicle-recorder"
}

variable "cluster_name" {
  description = "ECS cluster name"
  type        = string
  default     = "chronicle-cluster"
}

variable "task_family" {
  description = "ECS task definition family"
  type        = string
  default     = "chronicle-recorder-task"
}

variable "container_name" {
  description = "Name of the container inside the task"
  type        = string
  default     = "chronicle-recorder"
}

variable "cpu" {
  description = "Task CPU units"
  type        = number
  default     = 512
}

variable "memory" {
  description = "Task memory (MiB)"
  type        = number
  default     = 1024
}

variable "subnet_ids" {
  description = "List of subnet IDs for Fargate tasks"
  type        = list(string)
}

variable "security_group_ids" {
  description = "List of security group IDs for Fargate tasks"
  type        = list(string)
}

variable "vpc_cidr" {
  type = string 
}

variable "public_subnet_cidrs" {
  type = list(string) 
}
