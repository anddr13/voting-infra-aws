output "role_arn" {
  description = "IAM role for GitHub Actions."
  value       = aws_iam_role.github.arn
}

output "next_steps" {
  description = "Commands that finish the setup."
  value       = <<-EOT
    gh variable set AWS_ROLE_ARN --repo ${var.github_repo} --body "${aws_iam_role.github.arn}"
    gh variable set EKS_ADMIN_ARNS --repo ${var.github_repo} --body '["${data.aws_caller_identity.current.arn}"]'
    git add infra/backend.hcl && git commit -m "Add backend config" && git push
  EOT
}
