output "argocd_namespace" {
  value = helm_release.argocd.namespace
}

output "karpenter_node_role_name" {
  value = aws_iam_role.karpenter_node.name
}

output "karpenter_interruption_queue" {
  value = aws_sqs_queue.karpenter.name
}

output "keda_operator_role_arn" {
  description = "Put this in gitops/apps/keda.yaml's serviceAccount.annotations (replace the CHANGE-ME placeholder)."
  value       = aws_iam_role.keda_operator.arn
}

output "predictive_scaler_role_arn" {
  description = "Put this in k8s/predictive-scaling/serviceaccount.yaml's eks.amazonaws.com/role-arn annotation (replace the CHANGE-ME placeholder)."
  value       = aws_iam_role.predictive_scaler.arn
}
