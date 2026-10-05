mock_provider "aws" {}

variables {
  project          = "test"
  region           = "ap-northeast-1"
  ecr_image_uri    = "123456789012.dkr.ecr.ap-northeast-1.amazonaws.com/test-prod:abc123"
  certificate_arn  = "arn:aws:acm:ap-northeast-1:123456789012:certificate/test"
  rails_master_key = "0123456789abcdef0123456789abcdef"
  frontend_origin  = "https://app.example.com"
}

run "rails_master_key_is_written_through_write_only_argument" {
  command = plan

  assert {
    condition     = aws_secretsmanager_secret_version.rails_master_key.secret_string_wo_version == 1
    error_message = "rails_master_key must be stored with secret_string_wo so the value never reaches state."
  }
}
