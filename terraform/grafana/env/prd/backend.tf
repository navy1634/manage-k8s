terraform {
  backend "s3" {
    bucket       = "terraform-sandbox-prod.tfstate"
    key          = "grafana/terraform.tfstate"
    region       = "ap-southeast-2"
    profile      = "sandbox-prod"
    encrypt      = true
    use_lockfile = true
  }
}
