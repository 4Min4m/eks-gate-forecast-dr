# Predictive-scaler CronJob — IRSA role only. The CronJob itself (script +
# schedule) lives in GitOps (k8s/predictive-scaling/, Argo CD), because it's
# a plain workload with no Terraform-computed values beyond this role's ARN
# (same reasoning as keda.tf).
#
# This role is intentionally separate from the KEDA operator role above:
# the CronJob needs write access (PutMetricData) that the KEDA operator
# itself should never have — splitting them keeps each principal's blast
# radius to exactly what it does.
resource "aws_iam_role" "predictive_scaler" {
  name = "${var.cluster_name}-predictive-scaler-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = var.oidc_provider_arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.oidc_sub}:sub" = "system:serviceaccount:httpbin:predictive-scaler"
          "${local.oidc_sub}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })
  tags = { "kubernetes.io/cluster/${var.cluster_name}" = "owned" }
}

resource "aws_iam_policy" "predictive_scaler" {
  name        = "${var.cluster_name}-predictive-scaler-policy"
  description = "Read ALB RequestCount + publish forecast metric for ${var.cluster_name}"
  policy = templatefile("${path.module}/policies/predictive-scaler-policy.json.tpl", {
    custom_namespace = var.predictive_scaler_metric_namespace
  })
}

resource "aws_iam_role_policy_attachment" "predictive_scaler" {
  role       = aws_iam_role.predictive_scaler.name
  policy_arn = aws_iam_policy.predictive_scaler.arn
}
