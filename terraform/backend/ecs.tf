# S3 bucket for uploads
resource "aws_s3_bucket" "streams" {
  bucket = var.bucket_name

  lifecycle_rule {
    id      = "expire-old-objects"
    enabled = true
    expiration { days = 30 }
  }
}

# ECR repository
resource "aws_ecr_repository" "recorder" {
  name = var.ecr_repo_name
}

# CloudWatch Log Group
resource "aws_cloudwatch_log_group" "recorder" {
  name              = "/ecs/${var.task_family}"
  retention_in_days = 14
}

# ECS Cluster
resource "aws_ecs_cluster" "this" {
  name = var.cluster_name
}

# ECS Task Definition
resource "aws_ecs_task_definition" "recorder" {
  family                   = var.task_family
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.cpu
  memory                   = var.memory
  execution_role_arn       = aws_iam_role.ecs_exec_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([
    {
      name        = var.container_name
      image       = "${aws_ecr_repository.recorder.repository_url}:latest"
      essential   = true
      entryPoint  = ["/app/entrypoint.sh"]
      command     = []

      environment = [
        {
          name  = "DDB_TABLE"
          value = aws_dynamodb_table.jobs.name
        },
        {
          name  = "TTL_DAYS"
          value = "30"
        },
        {
          name  = "TRANSMISSION_TASK_DEF"
          value = aws_ecs_task_definition.transmission.arn
        },
        {
          name  = "ECS_CLUSTER"
          value = aws_ecs_cluster.this.name
        },
        {
          name  = "SUBNET_IDS"
          value = join(",", aws_public_subnet.public[*].id)
        },
        {
          name  = "SECURITY_GROUP_IDS"
          value = aws_security_group.ecs_tasks.id
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.recorder.name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = var.container_name
        }
      }
    }
  ])
}
