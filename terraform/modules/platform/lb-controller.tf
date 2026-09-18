# AWS Load Balancer Controller — IRSA role, scoped policy, Helm install.
resource "aws_iam_role" "alb_controller" {
  name = "${var.cluster_name}-alb-controller-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = var.oidc_provider_arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.oidc_sub}:sub" = "system:serviceaccount:kube-system:aws-load-balancer-controller"
          "${local.oidc_sub}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })
  tags = { "kubernetes.io/cluster/${var.cluster_name}" = "owned" }
}

resource "aws_iam_policy" "alb_controller" {
  name        = "${var.cluster_name}-AWSLoadBalancerControllerIAMPolicy"
  description = "AWS Load Balancer Controller policy for ${var.cluster_name}"
  policy = templatefile("${path.module}/policies/alb-controller-policy.json.tpl", {
    region       = var.region
    account_id   = local.account_id
    cluster_name = var.cluster_name
  })
}

resource "aws_iam_role_policy_attachment" "alb_controller" {
  role       = aws_iam_role.alb_controller.name
  policy_arn = aws_iam_policy.alb_controller.arn
}

resource "helm_release" "alb_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = var.alb_controller_chart_version
  namespace  = "kube-system"

  set {
    name  = "clusterName"
    value = var.cluster_name
  }
  set {
    name  = "serviceAccount.create"
    value = "true"
  }
  set {
    name  = "serviceAccount.name"
    value = "aws-load-balancer-controller"
  }
  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = aws_iam_role.alb_controller.arn
  }
  set {
    name  = "region"
    value = var.region
  }
  set {
    name  = "vpcId"
    value = var.vpc_id
  }

  depends_on = [aws_iam_role_policy_attachment.alb_controller]
}
