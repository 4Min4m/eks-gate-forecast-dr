resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = var.argocd_chart_version
  namespace        = "argocd"
  create_namespace = true

  values = [yamlencode({
    crds   = { install = true, keep = true }
    server = { service = { type = "ClusterIP" }, metrics = { enabled = true } }
    controller = { metrics = { enabled = true } }
  })]

  depends_on = [helm_release.alb_controller]
}
