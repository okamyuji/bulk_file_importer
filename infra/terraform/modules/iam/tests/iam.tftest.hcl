mock_provider "aws" {
  mock_data "aws_region" {
    defaults = {
      name = "ap-northeast-1"
    }
  }

  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }
}

variables {
  project            = "test"
  environment        = "prod"
  csv_bucket_arn     = "arn:aws:s3:::test-bucket"
  ecr_repository_arn = "arn:aws:ecr:ap-northeast-1:123456789012:repository/test-prod"
  secrets_arns = [
    "arn:aws:secretsmanager:ap-northeast-1:123456789012:secret:test-prod-rails-master-key-AbCdEf",
  ]
}

run "execution_role_is_scoped_to_given_repository_and_secrets" {
  command = apply

  assert {
    condition = {
      for s in jsondecode(aws_iam_role_policy.ecs_execution.policy).Statement : s.Sid => s.Resource
      } == {
      ECRAuth              = "*"
      ECRPull              = "arn:aws:ecr:ap-northeast-1:123456789012:repository/test-prod"
      CloudWatchLogs       = "arn:aws:logs:ap-northeast-1:123456789012:log-group:/ecs/test/*"
      SecretsManagerAccess = ["arn:aws:secretsmanager:ap-northeast-1:123456789012:secret:test-prod-rails-master-key-AbCdEf"]
    }
    error_message = "ECRPull and SecretsManagerAccess must not fall back to wildcards."
  }
}

run "rejects_empty_secrets_arns" {
  command = plan

  variables {
    secrets_arns = []
  }

  expect_failures = [var.secrets_arns]
}

run "rejects_non_ecr_repository_arn" {
  command = plan

  variables {
    ecr_repository_arn = "*"
  }

  expect_failures = [var.ecr_repository_arn]
}

# RDS が管理するマスターの secret は名前が "rds!" で始まる。
run "accepts_rds_managed_secret_arn" {
  command = plan

  variables {
    secrets_arns = ["arn:aws:secretsmanager:ap-northeast-1:123456789012:secret:rds!cluster-0123abcd-4567-89ef-0123-456789abcdef-AbCdEf"]
  }
}

run "rejects_wildcard_secrets_arn" {
  command = plan

  variables {
    secrets_arns = ["*"]
  }

  expect_failures = [var.secrets_arns]
}

run "rejects_wildcard_among_valid_secrets_arns" {
  command = plan

  variables {
    secrets_arns = [
      "arn:aws:secretsmanager:ap-northeast-1:123456789012:secret:test-prod-rails-master-key-AbCdEf",
      "arn:aws:secretsmanager:ap-northeast-1:123456789012:secret:*",
    ]
  }

  expect_failures = [var.secrets_arns]
}

run "rejects_non_secrets_manager_arn" {
  command = plan

  variables {
    secrets_arns = ["arn:aws:ssm:ap-northeast-1:123456789012:parameter/test"]
  }

  expect_failures = [var.secrets_arns]
}
