output "state_bucket" {
  description = "S3 bucket with the infra/ state."
  value       = aws_s3_bucket.state.bucket
}

output "next_steps" {
  description = "What to run next."
  value       = "make up      # infra/backend.hcl is in place"
}
