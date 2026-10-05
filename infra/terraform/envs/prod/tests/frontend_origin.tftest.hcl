mock_provider "aws" {}

variables {
  project          = "test"
  region           = "ap-northeast-1"
  ecr_image_uri    = "123456789012.dkr.ecr.ap-northeast-1.amazonaws.com/test-prod:abc123"
  certificate_arn  = "arn:aws:acm:ap-northeast-1:123456789012:certificate/test"
  rails_master_key = "0123456789abcdef0123456789abcdef"
  frontend_origin  = "https://app.example.com"
}

run "accepts_single_https_origin" {
  command = plan
}

run "accepts_multiple_https_origins_with_port" {
  command = plan

  variables {
    frontend_origin = "https://app.example.com,https://admin.example.com:8443"
  }
}

run "rejects_empty_origin" {
  command = plan

  variables {
    frontend_origin = ""
  }

  expect_failures = [var.frontend_origin]
}

run "rejects_http_origin" {
  command = plan

  variables {
    frontend_origin = "http://app.example.com"
  }

  expect_failures = [var.frontend_origin]
}

run "rejects_http_origin_among_https_origins" {
  command = plan

  variables {
    frontend_origin = "https://app.example.com,http://admin.example.com"
  }

  expect_failures = [var.frontend_origin]
}

run "rejects_empty_element" {
  command = plan

  variables {
    frontend_origin = "https://app.example.com,"
  }

  expect_failures = [var.frontend_origin]
}

# cors.rb splits on "," without stripping, so a space after the comma never matches a browser Origin.
run "rejects_space_after_comma" {
  command = plan

  variables {
    frontend_origin = "https://app.example.com, https://admin.example.com"
  }

  expect_failures = [var.frontend_origin]
}

run "rejects_origin_with_path" {
  command = plan

  variables {
    frontend_origin = "https://app.example.com/"
  }

  expect_failures = [var.frontend_origin]
}

run "rejects_wildcard_origin" {
  command = plan

  variables {
    frontend_origin = "*"
  }

  expect_failures = [var.frontend_origin]
}
