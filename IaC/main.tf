# Cluster AWS ECS
resource "aws_ecs_cluster" "ecs-cluster" {
    name = "${var.project_name}-${var.env}-cluster"  
}

# Logs do Cloudwatch
resource "aws_cloudwatch_log_group" "ecs-log-group" {
    name = "/ecs/${var.project_name}-${var.env}-task-definition"
}

# Tarefa ECS
resource "aws_ecs_task_definition" "ecs-task" {
    family                      = "${var.project_name}-${var.env}-task-definition"
    network_mode                = "awsvpc"
    requires_compatibilities    = ["FARGATE"]
    cpu                         = var.cpu
    memory                      = var.memory
    execution_role_arn          = "arn:aws:iam::068312484665:role/ecsTaskExecutionRole"
    task_role_arn               = "arn:aws:iam::068312484665:role/ecsTaskExecutionRole"

    container_definitions = jsonencode([
        {
            name      = "${var.project_name}-${var.env}-con"
            image     = var.docker_image_name # Nome da imagem docker com a aplicação WEB
            essential = true

            portMappings = [
                {
                containerPort   = tonumber(var.container_port)
                hostport        = tonumber(var.container_port)
                protocol        = "tcp"
                appProtocol     = "http"
                }
            ],

            # Adicionar variáveis de ambiente do S3
            enviromentFiles = [
                {
                value = var.s3_env_vars_file_arn,
                type  = "s3"
                }
            ]

            # Configurar AWS CloudWatch para o container
            logConfiguration = {
                logDriver = "awslogs"
                options = {
                    "awslogs-create-group"  = "true"
                    "awslogs-group"         = aws_cloudwatch_log_group.ecs-log-group.name
                    "awslogs-region"        = var.awslogs_region
                    "awslogs-stream-prefix" = "ecs"
                }
            }
        }
    ])
}

# Serviço do container ECS
resource "aws_ecs_service" "ecs-service" {
    name            = "${var.project_name}-service"
    launch_type     = "FARGATE"
    cluster         = aws_ecs_cluster.ecs-cluster.id
    task_definition = aws_ecs_task_definition.ecs-task.arn
    desired_count   = 1

    network_configuration {
      assign_public_ip  = true
      subnets           = [module.vpc.public_subnets[0]]
      security_groups   = [module.container-security-group.security_group_id]
    }

    health_check_grace_period_seconds = 0

    load_balancer {
      target_group_arn  = aws_lb_target_group.ecs-target-group.arn
      container_name    = "${var.project_name}-${var.env}-con"
      container_port    = var.container_port
    }

}

# Load Balancer
resource "aws_lb" "ecs-lb" {
    name                = "${var.project_name}-${var.env}-alb"
    internal            = false
    load_balancer_type  = "application"
    security_groups     = [module.alb-security-group.security_group_id]
    subnets             = [module.vpc.public_subnets[0], module.vpc.public_subnets[1]]
  
}

# Target Group do Load Balancer
resource "aws_lb_target_group" "ecs-target-group" {
    name            = "${var.project_name}-${var.env}-target-group"
    port            = var.container_port
    protocol        = "HTTP"
    target_type     = "ip"
    vpc_id          = module.vpc.vpc_id

    health_check {
      path                  = var.health_check_path
      protocol              = "HTTP"
      matcher               = "200-299"
      interval              = 30
      timeout               = 5
      healthy_threshold     = 5
      unhealthy_threshold   = 2
    }
}

# Listener do Load Balancer
resource "aws_lb_listener" "ecs-listener" {
    load_balancer_arn   = aws_lb.ecs-lb.arn
    port                = 80
    protocol            = "HTTP"

    default_action {
      type                  = "forward"
      target_group_arn      = aws_lb_target_group.ecs-target-group.arn
    }
}