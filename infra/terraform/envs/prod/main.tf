locals {
  availability_zones = ["${var.region}a", "${var.region}c"]

  ecr_image_uri_pattern = "^(?P<account>[0-9]{12})\\.dkr\\.ecr\\.(?P<region>[a-z0-9-]+)\\.amazonaws\\.com/(?P<repository>[a-z0-9._/-]+)(?::[A-Za-z0-9._-]+|@sha256:[0-9a-f]{64})$"
  ecr_image             = regex(local.ecr_image_uri_pattern, var.ecr_image_uri)
  ecr_repository_arn    = "arn:aws:ecr:${local.ecr_image.region}:${local.ecr_image.account}:repository/${local.ecr_image.repository}"

  common_tags = {
    Project     = var.project
    Environment = var.environment
  }

  rails_environment = {
    RAILS_ENV           = "production"
    RAILS_LOG_TO_STDOUT = "1"
    DATABASE_HOST       = module.rds_aurora.cluster_endpoint
    DATABASE_PORT       = tostring(module.rds_aurora.port)
    DATABASE_NAME       = module.rds_aurora.database_name
    S3_BUCKET           = module.s3_csv_bucket.bucket_name
    AWS_REGION          = var.region
    FRONTEND_ORIGIN     = var.frontend_origin
  }

  # web と worker はローテーションしないアプリ用の secret を使う。マスターの secret は
  # 7日ごとに替わり、起動済みのタスクには新しい値が届かないため、migrate タスクだけが使う。
  app_db_environment = merge(local.rails_environment, {
    DATABASE_USERNAME = var.app_db_username
  })

  app_db_secrets = {
    RAILS_MASTER_KEY  = aws_secretsmanager_secret.rails_master_key.arn
    DATABASE_PASSWORD = aws_secretsmanager_secret.app_db_password.arn
  }
}

################################################################################
# Network
################################################################################

module "network" {
  source = "../../modules/network"

  project              = var.project
  environment          = var.environment
  vpc_cidr             = "10.1.0.0/16"
  availability_zones   = local.availability_zones
  public_subnet_cidrs  = ["10.1.1.0/24", "10.1.2.0/24"]
  private_subnet_cidrs = ["10.1.11.0/24", "10.1.12.0/24"]
  single_nat_gateway   = false

  tags = local.common_tags
}

################################################################################
# Observability (log groups needed by ECS services)
################################################################################

module "observability" {
  source = "../../modules/observability"

  project           = var.project
  environment       = var.environment
  retention_in_days = 30

  tags = local.common_tags
}

################################################################################
# SecretsManager
################################################################################

resource "aws_secretsmanager_secret" "rails_master_key" {
  name        = "${var.project}-${var.environment}-rails-master-key"
  description = "Rails master key for credentials decryption"

  tags = local.common_tags
}

resource "aws_secretsmanager_secret_version" "rails_master_key" {
  secret_id        = aws_secretsmanager_secret.rails_master_key.id
  secret_string_wo = var.rails_master_key
  # write-only の値は state に無く差分を取れない。鍵を替えたらこの数を上げないと新しい値が送られない。
  secret_string_wo_version = 1
}

ephemeral "random_password" "app_db_password" {
  length = 32
  # database.yml は値を引用符なしで YAML に埋め込むため、記号を含めない。
  special = false
}

resource "aws_secretsmanager_secret" "app_db_password" {
  name        = "${var.project}-${var.environment}-app-db-password"
  description = "Password of the DML-only MySQL user that the web and worker services connect as"

  tags = local.common_tags
}

resource "aws_secretsmanager_secret_version" "app_db_password" {
  secret_id        = aws_secretsmanager_secret.app_db_password.id
  secret_string_wo = ephemeral.random_password.app_db_password.result
  # 乱数は plan のたびに変わるが、送られるのはこの数を上げたときだけ。替える手順は README 参照。
  secret_string_wo_version = 1
}

################################################################################
# RDS Aurora
################################################################################

module "rds_aurora" {
  source = "../../modules/rds_aurora"

  project         = var.project
  environment     = var.environment
  vpc_id          = module.network.vpc_id
  subnet_ids      = module.network.private_subnet_ids
  sg_id           = module.network.sg_rds_id
  instance_class  = "db.r6g.large"
  instance_count  = 2
  database_name   = var.db_name
  master_username = var.db_username

  backup_retention_period = 7
  deletion_protection     = true
  skip_final_snapshot     = false
  storage_encrypted       = true

  tags = local.common_tags
}

################################################################################
# S3 CSV Bucket
################################################################################

module "s3_csv_bucket" {
  source = "../../modules/s3_csv_bucket"

  project                     = var.project
  environment                 = var.environment
  csv_imports_expiration_days = 7
  originals_expiration_days   = 90
  force_destroy               = false

  tags = local.common_tags
}

################################################################################
# IAM
################################################################################

module "iam" {
  source = "../../modules/iam"

  project            = var.project
  environment        = var.environment
  csv_bucket_arn     = module.s3_csv_bucket.bucket_arn
  ecr_repository_arn = local.ecr_repository_arn
  secrets_arns = [
    aws_secretsmanager_secret.rails_master_key.arn,
    aws_secretsmanager_secret.app_db_password.arn,
    module.rds_aurora.master_secret_arn,
  ]

  tags = local.common_tags
}

################################################################################
# ECS Cluster
################################################################################

module "ecs_cluster" {
  source = "../../modules/ecs_cluster"

  project            = var.project
  environment        = var.environment
  container_insights = true

  tags = local.common_tags
}

################################################################################
# ECS Service - Web
################################################################################

module "ecs_service_web" {
  source = "../../modules/ecs_service_web"

  project               = var.project
  environment           = var.environment
  cluster_id            = module.ecs_cluster.cluster_id
  vpc_id                = module.network.vpc_id
  private_subnet_ids    = module.network.private_subnet_ids
  public_subnet_ids     = module.network.public_subnet_ids
  security_group_ids    = [module.network.sg_rails_web_id]
  alb_security_group_id = module.network.sg_alb_id
  task_role_arn         = module.iam.task_role_arn
  execution_role_arn    = module.iam.execution_role_arn
  ecr_image_uri         = var.ecr_image_uri
  cpu                   = 1024
  memory                = 2048
  desired_count         = 2
  log_group_name        = module.observability.log_group_web_name
  certificate_arn       = var.certificate_arn

  environment_variables = local.app_db_environment
  secrets               = local.app_db_secrets

  tags = local.common_tags
}

################################################################################
# ECS Service - Worker
################################################################################

module "ecs_service_worker" {
  source = "../../modules/ecs_service_worker"

  project            = var.project
  environment        = var.environment
  cluster_id         = module.ecs_cluster.cluster_id
  private_subnet_ids = module.network.private_subnet_ids
  security_group_ids = [module.network.sg_rails_worker_id]
  task_role_arn      = module.iam.task_role_arn
  execution_role_arn = module.iam.execution_role_arn
  ecr_image_uri      = var.ecr_image_uri
  cpu                = 512
  memory             = 1024
  desired_count      = 2
  min_capacity       = 2
  max_capacity       = 4
  cpu_target_value   = 70
  log_group_name     = module.observability.log_group_worker_name

  environment_variables = local.app_db_environment
  secrets               = local.app_db_secrets

  tags = local.common_tags
}

################################################################################
# ECS Task Definition - Migrate (run once per deploy with aws ecs run-task)
################################################################################

resource "aws_ecs_task_definition" "migrate" {
  family                   = "${var.project}-${var.environment}-migrate"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 512
  memory                   = 1024
  task_role_arn            = module.iam.task_role_arn
  execution_role_arn       = module.iam.execution_role_arn

  container_definitions = jsonencode([
    {
      name      = "${var.project}-${var.environment}-migrate"
      image     = var.ecr_image_uri
      essential = true
      # runtime は shell の無い distroless のため、Dockerfile の CMD と同じく ruby から直接起動する。
      command = ["ruby", "bin/rails", "db:prepare", "db:grant_app_user"]

      environment = [
        for k, v in merge(local.rails_environment, {
          DATABASE_USERNAME     = var.db_username
          DATABASE_APP_USERNAME = var.app_db_username
        }) : { name = k, value = v }
      ]

      secrets = [
        { name = "RAILS_MASTER_KEY", valueFrom = aws_secretsmanager_secret.rails_master_key.arn },
        { name = "DATABASE_PASSWORD", valueFrom = "${module.rds_aurora.master_secret_arn}:password::" },
        { name = "DATABASE_APP_PASSWORD", valueFrom = aws_secretsmanager_secret.app_db_password.arn },
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = module.observability.log_group_worker_name
          "awslogs-region"        = var.region
          "awslogs-stream-prefix" = "migrate"
        }
      }
    }
  ])

  tags = local.common_tags
}

################################################################################
# Outputs
################################################################################

output "migrate_task_definition_arn" {
  value = aws_ecs_task_definition.migrate.arn
}

output "cluster_name" {
  value = module.ecs_cluster.cluster_name
}

output "private_subnet_ids" {
  value = module.network.private_subnet_ids
}

output "migrate_security_group_id" {
  value = module.network.sg_rails_worker_id
}
