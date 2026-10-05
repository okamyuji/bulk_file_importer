# bucket と region は環境ごとに異なるため、terraform init -backend-config で渡す（README 参照）。
terraform {
  backend "s3" {
    key          = "prod/terraform.tfstate"
    encrypt      = true
    use_lockfile = true
  }
}
