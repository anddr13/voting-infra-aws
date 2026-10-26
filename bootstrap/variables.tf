variable "region" {
  description = "AWS region for the state bucket (keep it equal to the infra region)."
  type        = string
  default     = "eu-north-1"
}

variable "env" {
  description = "Environment name, used in the state key."
  type        = string
  default     = "dev"
}

variable "budget_email" {
  description = "Where budget alerts go (`make bootstrap` passes your git user.email)."
  type        = string
}

variable "budget_limit_usd" {
  description = "Monthly budget; alerts at 50% actual and 100% forecasted spend."
  type        = string
  default     = "10"
}
