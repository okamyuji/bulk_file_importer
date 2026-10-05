locals {
  availability_zones = ["${var.region}a", "${var.region}c"]

  ecr_image_uri_pattern = "^(?P<account>[0-9]{12})\\.dkr\\.ecr\\.(?P<region>[a-z0-9-]+)\\.amazonaws\\.com/(?P<repository>[a-z0-9._/-]+)(?::[A-Za-z0-9._-]+|@sha256:[0-9a-f]{64})$"
  ecr_image             = regex(local.ecr_image_uri_pattern, var.ecr_image_uri)
  ecr_repository_arn    = "arn:aws:ecr:${local.ecr_image.region}:${local.ecr_image.account}:repository/${local.ecr_image.repository}"

  common_tags = {
    Project     = var.project
    Environment = var.environment
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

  environment_variables = {
    RAILS_ENV           = "production"
    RAILS_LOG_TO_STDOUT = "1"
    DATABASE_HOST       = module.rds_aurora.cluster_endpoint
    DATABASE_PORT       = tostring(module.rds_aurora.port)
    DATABASE_NAME       = module.rds_aurora.database_name
    DATABASE_USERNAME   = var.db_username
    S3_BUCKET           = module.s3_csv_bucket.bucket_name
    AWS_REGION          = var.region
    FRONTEND_ORIGIN     = var.frontend_origin
  }

  secrets = {
    RAILS_MASTER_KEY  = aws_secretsmanager_secret.rails_master_key.arn
    DATABASE_PASSWORD = "${module.rds_aurora.master_secret_arn}:password::"
  }

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

  environment_variables = {
    RAILS_ENV           = "production"
    RAILS_LOG_TO_STDOUT = "1"
    DATABASE_HOST       = module.rds_aurora.cluster_endpoint
    DATABASE_PORT       = tostring(module.rds_aurora.port)
    DATABASE_NAME       = module.rds_aurora.database_name
    DATABASE_USERNAME   = var.db_username
    S3_BUCKET           = module.s3_csv_bucket.bucket_name
    AWS_REGION          = var.region
    FRONTEND_ORIGIN     = var.frontend_origin
  }

  secrets = {
    RAILS_MASTER_KEY  = aws_secretsmanager_secret.rails_master_key.arn
    DATABASE_PASSWORD = "${module.rds_aurora.master_secret_arn}:password::"
  }

  tags = local.common_tags
}
