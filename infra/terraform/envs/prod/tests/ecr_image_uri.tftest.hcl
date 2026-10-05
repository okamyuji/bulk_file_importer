mock_provider "aws" {}

variables {
  project          = "test"
  region           = "ap-northeast-1"
  ecr_image_uri    = "123456789012.dkr.ecr.ap-northeast-1.amazonaws.com/team/test-prod:abc123"
  certificate_arn  = "arn:aws:acm:ap-northeast-1:123456789012:certificate/test"
  rails_master_key = "not-a-real-key"
  frontend_origin  = "https://app.example.com"
}

run "derives_repository_arn_from_tagged_image_uri" {
  command = plan

  assert {
    condition     = local.ecr_repository_arn == "arn:aws:ecr:ap-northeast-1:123456789012:repository/team/test-prod"
    error_message = "The ECR repository ARN must be derived from ecr_image_uri."
  }
}

run "derives_repository_arn_from_digest_image_uri" {
  command = plan

  variables {
    ecr_image_uri = "123456789012.dkr.ecr.ap-northeast-1.amazonaws.com/test-prod@sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
  }

  assert {
    condition     = local.ecr_repository_arn == "arn:aws:ecr:ap-northeast-1:123456789012:repository/test-prod"
    error_message = "The ECR repository ARN must be derived from ecr_image_uri."
  }
}

run "rejects_non_ecr_image_uri" {
  command = plan

  variables {
    ecr_image_uri = "docker.io/library/ruby:3.4"
  }

  expect_failures = [var.ecr_image_uri]
}
