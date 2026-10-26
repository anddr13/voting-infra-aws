# One-time setup, run from a laptop with local state (`make bootstrap`, see README):
#   - S3 bucket for the main stack's state (native S3 locking, no DynamoDB);
#   - a monthly budget with e-mail alerts, the safety net for a stack that has no nightly destroy.
# Costs ~$0 and is meant to stay; only infra/ is created and destroyed.
#
# Unlike the Azure and GCP stacks there is no GitHub OIDC trust here: this account lives in an
# AWS-managed organization whose SCP denies iam:CreateOpenIDConnectProvider, so Terraform runs from
# the laptop with short-lived `aws login` credentials instead of from GitHub Actions.

terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.70"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.9"
    }
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      project    = "voting"
      managed-by = "terraform-bootstrap"
    }
  }
}

data "aws_caller_identity" "current" {}

# --- Terraform state -----------------------------------------------------------

resource "aws_s3_bucket" "state" {
  bucket = "voting-tfstate-${data.aws_caller_identity.current.account_id}-${var.region}"
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket = aws_s3_bucket.state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# --- Cost alerts -------------------------------------------------------------------

resource "aws_budgets_budget" "monthly" {
  name         = "voting-sandbox"
  budget_type  = "COST"
  limit_amount = var.budget_limit_usd
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  # Forecast first: it fires while a forgotten cluster is still running, not after the money is spent.
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = [var.budget_email]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 50
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.budget_email]
  }
}

# --- Wiring for infra/ ---------------------------------------------------------------

# Not committed (see .gitignore): it carries the account ID and only the laptop ever needs it.
resource "local_file" "backend" {
  filename        = "${path.module}/../infra/backend.hcl"
  file_permission = "0644"
  content         = <<-EOT
    bucket       = "${aws_s3_bucket.state.bucket}"
    key          = "voting/${var.env}/terraform.tfstate"
    region       = "${var.region}"
    use_lockfile = true
  EOT
}
