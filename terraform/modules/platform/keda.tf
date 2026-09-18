# KEDA — IRSA role only. KEDA itself is installed via Argo CD (Helm), same
# pattern as kube-prometheus-stack: it needs no Terraform-computed values
# except this role's ARN, which is deterministic (account_id + cluster_name
# are known ahead of time), so it's referenced as a plain string in
# gitops/apps/keda.yaml rather than threading a Terraform output into GitOps.
#
# Why KEDA needs AWS IAM at all (unlike kube-prometheus-stack): the
# `aws-cloudwatch` scaler trigger polls CloudWatch directly from the KEDA
# operator pod, so the operator's own service account needs IRSA — this is
# the same shape as the ALB Controller/EBS CSI roles above, just for a
# GitOps-installed component instead of a Terraform-installed one.
resource "aws_iam_role" "keda_operator" {
  name = "${var.cluster_name}-keda-operator-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = var.oidc_provider_arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.oidc_sub}:sub" = "system:serviceaccount:keda:keda-operator"
          "${local.oidc_sub}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })
  tags = { "kubernetes.io/cluster/${var.cluster_name}" = "owned" }
}

resource "aws_iam_policy" "keda_operator" {
  name        = "${var.cluster_name}-keda-operator-policy"
  description = "Read-only CloudWatch access for KEDA's aws-cloudwatch scaler (${var.cluster_name})"
  policy      = file("${path.module}/policies/keda-operator-policy.json")
}

resource "aws_iam_role_policy_attachment" "keda_operator" {
  role       = aws_iam_role.keda_operator.name
  policy_arn = aws_iam_policy.keda_operator.arn
}
