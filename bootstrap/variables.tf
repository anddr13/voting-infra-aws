variable "region" {
  description = "AWS region for the state bucket (keep it equal to the infra region)."
  type        = string
  default     = "eu-central-1"
}

variable "env" {
  description = "Environment name, used in the state key."
  type        = string
  default     = "dev"
}

variable "github_repo" {
  description = "owner/name of the repository whose workflows may assume the role."
  type        = string
  default     = "anddr13/voting-infra-aws"
}
