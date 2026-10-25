# Terraform installs only Argo CD and one "root" Application. Everything else in the cluster
# (Traefik, KEDA, Strimzi, Kafka, Redis, MongoDB, the app) comes from voting-gitops.

locals {
  cloud = "aws"

  # Argo CD does not assess the health of child Applications by default, so sync waves
  # in an app of apps would not wait for the operators. This restores it.
  application_health_lua = <<-EOT
    hs = {}
    hs.status = "Progressing"
    hs.message = ""
    if obj.status ~= nil and obj.status.health ~= nil then
      hs.status = obj.status.health.status
      if obj.status.health.message ~= nil then
        hs.message = obj.status.health.message
      end
    end
    return hs
  EOT
}

resource "helm_release" "argocd" {
  name             = "argocd"
  namespace        = "argocd"
  create_namespace = true
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = var.argocd_chart_version
  timeout          = 900

  values = [yamlencode({
    dex           = { enabled = false }
    notifications = { enabled = false }
    configs = {
      cm = {
        "resource.customizations.health.argoproj.io_Application" = local.application_health_lua
      }
    }
  })]

  depends_on = [aws_eks_node_group.this, kubernetes_storage_class_v1.gp3]
}

resource "helm_release" "root_app" {
  name       = "root-app"
  namespace  = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argocd-apps"
  version    = var.argocd_apps_chart_version

  values = [yamlencode({
    applications = {
      root = {
        namespace  = "argocd"
        project    = "default"
        finalizers = ["resources-finalizer.argocd.argoproj.io"]
        source = {
          repoURL        = var.gitops_repo_url
          targetRevision = var.gitops_revision
          path           = "apps"
          helm = {
            valueFiles = ["values.yaml", "../envs/${local.cloud}.yaml"]
          }
        }
        destination = {
          server    = "https://kubernetes.default.svc"
          namespace = "argocd"
        }
        syncPolicy = {
          automated = { prune = true, selfHeal = true }
        }
      }
    }
  })]

  depends_on = [helm_release.argocd]
}
