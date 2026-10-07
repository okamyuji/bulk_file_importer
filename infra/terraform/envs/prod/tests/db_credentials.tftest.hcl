mock_provider "aws" {

  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::123456789012:role/test"
    }
  }

  mock_resource "aws_lb" {
    defaults = {
      arn = "arn:aws:elasticloadbalancing:ap-northeast-1:123456789012:loadbalancer/app/test/0123"
    }
  }

  mock_resource "aws_lb_target_group" {
    defaults = {
      arn = "arn:aws:elasticloadbalancing:ap-northeast-1:123456789012:targetgroup/test/0123"
    }
  }

  mock_resource "aws_ecs_cluster" {
    defaults = {
      id = "arn:aws:ecs:ap-northeast-1:123456789012:cluster/test"
    }
  }
}

override_resource {
  target = aws_secretsmanager_secret.app_db_password
  values = {
    arn = "arn:aws:secretsmanager:ap-northeast-1:123456789012:secret:test-prod-app-db-password-AbCdEf"
  }
}

override_resource {
  target = aws_secretsmanager_secret.rails_master_key
  values = {
    arn = "arn:aws:secretsmanager:ap-northeast-1:123456789012:secret:test-prod-rails-master-key-AbCdEf"
  }
}

override_resource {
  target = module.rds_aurora.aws_rds_cluster.this
  values = {
    master_user_secret = [{
      secret_arn = "arn:aws:secretsmanager:ap-northeast-1:123456789012:secret:rds!cluster-master-AbCdEf"
    }]
  }
}

variables {
  project          = "test"
  region           = "ap-northeast-1"
  ecr_image_uri    = "123456789012.dkr.ecr.ap-northeast-1.amazonaws.com/test-prod:abc123"
  certificate_arn  = "arn:aws:acm:ap-northeast-1:123456789012:certificate/test"
  rails_master_key = "not-a-real-key"
  frontend_origin  = "https://app.example.com"
}

run "web_and_worker_connect_as_app_user_with_app_secret" {
  command = apply

  assert {
    condition = alltrue([
      for definitions in [
        module.ecs_service_web.container_definitions,
        module.ecs_service_worker.container_definitions,
      ] :
      contains(jsondecode(definitions)[0].environment, { name = "DATABASE_USERNAME", value = "app" }) &&
      contains(jsondecode(definitions)[0].secrets, { name = "DATABASE_PASSWORD", valueFrom = "arn:aws:secretsmanager:ap-northeast-1:123456789012:secret:test-prod-app-db-password-AbCdEf" })
    ])
    error_message = "web and worker must connect as app_db_username with the app password secret."
  }

  assert {
    condition = alltrue([
      for definitions in [
        module.ecs_service_web.container_definitions,
        module.ecs_service_worker.container_definitions,
      ] :
      length(regexall("rds!cluster-master", definitions)) == 0
    ])
    error_message = "web and worker must not receive the rotated master secret."
  }
}

run "migrate_task_connects_as_master_and_grants_app_user" {
  command = apply

  assert {
    condition = jsondecode(aws_ecs_task_definition.migrate.container_definitions)[0].command == [
      "ruby", "bin/rails", "db:prepare", "db:grant_app_user",
    ]
    error_message = "The migrate task must prepare the databases and then grant the app user."
  }

  assert {
    condition = (
      contains(jsondecode(aws_ecs_task_definition.migrate.container_definitions)[0].environment, { name = "DATABASE_USERNAME", value = "admin" }) &&
      contains(jsondecode(aws_ecs_task_definition.migrate.container_definitions)[0].environment, { name = "DATABASE_APP_USERNAME", value = "app" })
    )
    error_message = "The migrate task must connect as the master user and grant to app_db_username."
  }

  assert {
    condition = jsondecode(aws_ecs_task_definition.migrate.container_definitions)[0].secrets == [
      { name = "RAILS_MASTER_KEY", valueFrom = "arn:aws:secretsmanager:ap-northeast-1:123456789012:secret:test-prod-rails-master-key-AbCdEf" },
      { name = "DATABASE_PASSWORD", valueFrom = "arn:aws:secretsmanager:ap-northeast-1:123456789012:secret:rds!cluster-master-AbCdEf:password::" },
      { name = "DATABASE_APP_PASSWORD", valueFrom = "arn:aws:secretsmanager:ap-northeast-1:123456789012:secret:test-prod-app-db-password-AbCdEf" },
    ]
    error_message = "The migrate task must read the master password from the RDS secret and the app password from the app secret."
  }
}

run "app_db_password_is_written_through_write_only_argument" {
  command = plan

  assert {
    condition     = aws_secretsmanager_secret_version.app_db_password.secret_string_wo_version == 1
    error_message = "The app password must be stored with secret_string_wo so the value never reaches state."
  }
}

run "rejects_app_db_username_equal_to_master" {
  command = plan

  variables {
    app_db_username = "admin"
  }

  expect_failures = [var.app_db_username]
}

run "rejects_app_db_username_longer_than_32_characters" {
  command = plan

  variables {
    app_db_username = "a23456789012345678901234567890123"
  }

  expect_failures = [var.app_db_username]
}

run "accepts_app_db_username_of_32_characters" {
  command = plan

  variables {
    app_db_username = "a2345678901234567890123456789012"
  }
}
