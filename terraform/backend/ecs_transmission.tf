# Transmission container
resource "aws_ecs_task_definition" "transmission" {
  family                   = "${var.environment}-transmission"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = aws_iam_role.ecs_exec_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn
  
  container_definitions = jsonencode([
    {
      name      = "chronicle-transmission"
      image     = "${aws_ecr_repository.transmission.repository_url}:latest"
      essential = true
      
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.transmission.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "transmission"
        }
      }
      
      mountPoints = [
        {
          sourceVolume  = "downloads"
          containerPath = "/downloads"
          readOnly      = false
        },
        {
          sourceVolume  = "watch"
          containerPath = "/watch"
          readOnly      = false
        },
        {
          sourceVolume  = "config"
          containerPath = "/config"
          readOnly      = false
        }
      ]
      
      portMappings = [
        {
          containerPort = 9091
          hostPort      = 9091
          protocol      = "tcp"
        },
        {
          containerPort = 51413
          hostPort      = 51413
          protocol      = "tcp"
        },
        {
          containerPort = 51413
          hostPort      = 51413
          protocol      = "udp"
        }
      ]
    }
  ])
  
  volume {
    name = "downloads"
    
    efs_volume_configuration {
      file_system_id = aws_efs_file_system.transmission_data.id
      root_directory = "/downloads"
    }
  }
  
  volume {
    name = "watch"
    
    efs_volume_configuration {
      file_system_id = aws_efs_file_system.transmission_data.id
      root_directory = "/watch"
    }
  }
  
  volume {
    name = "config"
    
    efs_volume_configuration {
      file_system_id = aws_efs_file_system.transmission_data.id
      root_directory = "/config"
    }
  }
}

# ECR repository for the transmission container
resource "aws_ecr_repository" "transmission" {
  name = "${var.environment}-transmission"
}

# CloudWatch log group for transmission
resource "aws_cloudwatch_log_group" "transmission" {
  name              = "/ecs/${var.environment}-transmission"
  retention_in_days = 7
}

# EFS file system for transmission data
resource "aws_efs_file_system" "transmission_data" {
  creation_token = "${var.environment}-transmission-data"
  
  lifecycle_policy {
    transition_to_ia = "AFTER_30_DAYS"
  }
  
  tags = {
    Name = "${var.environment}-transmission-data"
  }
}

# EFS mount targets in each subnet
resource "aws_efs_mount_target" "transmission" {
  count           = length(aws_public_subnet.public)
  file_system_id  = aws_efs_file_system.transmission_data.id
  subnet_id       = aws_public_subnet.public[count.index].id
  security_groups = [aws_security_group.efs.id]
}

# Security group for EFS
resource "aws_security_group" "efs" {
  name        = "${var.environment}-efs-sg"
  description = "Allow EFS traffic from ECS tasks"
  vpc_id      = aws_vpc.this.id
  
  ingress {
    description     = "NFS from ECS tasks"
    from_port       = 2049
    to_port         = 2049
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_tasks.id]
  }
  
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
} 