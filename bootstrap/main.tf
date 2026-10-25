# One-time setup, run from a laptop with local state (see README):
#   - S3 bucket for the main stack's state (native S3 locking, no DynamoDB);
#   - GitHub OIDC provider + IAM role, so GitHub Actions gets short-lived credentials
#     and no AWS keys are stored in GitHub.
# Costs ~$0 and is meant to stay; only infra/ is created and destroyed daily.

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
    http = {
      source  = "hashicorp/http"
      version = "~> 3.6"
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

# --- GitHub Actions identity -------------------------------------------------------

# One per account. If it already exists: terraform import aws_iam_openid_connect_provider.github <arn>
resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}

data "aws_iam_policy_document" "github_assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Only workflows running on main of this one repository (immutable subject, see github.tf).
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = [local.github_subject]
    }
  }
}

resource "aws_iam_role" "github" {
  name               = "voting-infra-github"
  assume_role_policy = data.aws_iam_policy_document.github_assume.json
}

# Broad on purpose for a sandbox account: the stack creates VPCs, IAM roles and EKS.
# For anything real, scope this down to the services the stack uses.
resource "aws_iam_role_policy_attachment" "github" {
  role       = aws_iam_role.github.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# --- Wiring for infra/ ---------------------------------------------------------------

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
