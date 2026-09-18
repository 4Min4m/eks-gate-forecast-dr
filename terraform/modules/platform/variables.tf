variable "cluster_name" { type = string }
variable "cluster_version" { type = string }
variable "region" { type = string }
variable "vpc_id" { type = string }

# From the eks module
variable "oidc_provider_arn" { type = string }
variable "oidc_issuer_url" { type = string }

# Pinned chart versions (verify with `helm search repo ... --versions`)
variable "alb_controller_chart_version" {
  type    = string
  default = "1.8.1"
}
variable "argocd_chart_version" {
  type    = string
  default = "7.7.11"
}
variable "karpenter_chart_version" {
  type    = string
  default = "1.1.1"
}

# Karpenter NodePool tuning (differs per environment)
variable "karpenter_instance_categories" {
  type    = list(string)
  default = ["t", "m"]
}
variable "karpenter_capacity_types" {
  type        = list(string)
  description = "on-demand and/or spot"
  default     = ["spot", "on-demand"]
}
variable "karpenter_cpu_limit" {
  type        = string
  description = "Max total vCPUs Karpenter may provision for this pool"
  default     = "100"
}

# Predictive scaling (Phase 3 POC)
variable "predictive_scaler_metric_namespace" {
  type        = string
  description = "CloudWatch custom namespace the predictive-scaler CronJob publishes its forecast metric to. Scoped tightly in IAM so PutMetricData can't write anywhere else."
  default     = "httpbin/predictive-scaling"
}
