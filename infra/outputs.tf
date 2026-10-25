output "cluster_name" {
  description = "EKS cluster name."
  value       = aws_eks_cluster.this.name
}

output "kubeconfig_command" {
  description = "eval \"$(terraform output -raw kubeconfig_command)\": kubectl access through a separate kubeconfig file; ~/.kube/config is not touched. Your identity must be in admin_principal_arns."
  value       = "export KUBECONFIG=\"$HOME/.kube/voting-aws\" && aws eks update-kubeconfig --name ${aws_eks_cluster.this.name} --region ${var.region}"
}

output "argocd_ui" {
  description = "Argo CD UI via port-forward; the admin password is in the argocd-initial-admin-secret."
  value       = "kubectl -n argocd port-forward svc/argocd-server 8443:443"
}
