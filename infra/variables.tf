variable "region" {
  description = "AWS region."
  type        = string
  default     = "eu-north-1"
}

variable "env" {
  description = "Environment name, part of every resource name."
  type        = string
  default     = "dev"
}

variable "kubernetes_version" {
  description = "EKS Kubernetes version. null = the current EKS default."
  type        = string
  default     = null
}

variable "node_capacity_type" {
  description = "SPOT is ~3x cheaper, but this account's organization SCP denies Spot launches, hence ON_DEMAND."
  type        = string
  default     = "ON_DEMAND"

  validation {
    condition     = contains(["SPOT", "ON_DEMAND"], var.node_capacity_type)
    error_message = "node_capacity_type must be SPOT or ON_DEMAND."
  }
}

variable "node_instance_types" {
  description = "2 vCPU / 8 GiB types offered in eu-north-1; On-Demand uses the first, Spot would spread across all."
  type        = list(string)
  default     = ["m6i.large", "m7i.large", "m5.large", "m7a.large"]
}

variable "node_count" {
  description = "Number of worker nodes."
  type        = number
  default     = 2
}

variable "admin_principal_arns" {
  description = "IAM users/roles that get cluster-admin (e.g. your own identity, for kubectl from a laptop)."
  type        = list(string)
  default     = []
}

variable "gitops_repo_url" {
  description = "Repository Argo CD syncs from."
  type        = string
  default     = "https://github.com/anddr13/voting-gitops.git"
}

variable "gitops_revision" {
  description = "Branch or tag of the GitOps repository."
  type        = string
  default     = "main"
}

variable "argocd_chart_version" {
  description = "argo-cd Helm chart version."
  type        = string
  default     = "10.10.5"
}

variable "argocd_apps_chart_version" {
  description = "argocd-apps Helm chart version."
  type        = string
  default     = "2.0.7"
}
