# ===========================================================================
# Karpenter — dynamic, right-sized node provisioning.
# The system managed node group (in the eks module) runs Karpenter itself and
# core controllers; Karpenter then provisions all application nodes on demand.
# ===========================================================================

# --- Node IAM role (for instances Karpenter launches) ----------------------
resource "aws_iam_role" "karpenter_node" {
  name = "${var.cluster_name}-karpenter-node"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Action = "sts:AssumeRole", Effect = "Allow", Principal = { Service = "ec2.amazonaws.com" } }]
  })
}

resource "aws_iam_role_policy_attachment" "karpenter_node" {
  for_each = toset([
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
  ])
  policy_arn = each.value
  role       = aws_iam_role.karpenter_node.name
}

# Let Karpenter-launched nodes join the cluster (modern access entry, not aws-auth).
resource "aws_eks_access_entry" "karpenter_node" {
  cluster_name  = var.cluster_name
  principal_arn = aws_iam_role.karpenter_node.arn
  type          = "EC2_LINUX"
}

# --- Interruption handling: SQS queue fed by EventBridge -------------------
resource "aws_sqs_queue" "karpenter" {
  name                      = "${var.cluster_name}-karpenter"
  message_retention_seconds = 300
  sqs_managed_sse_enabled   = true
}

resource "aws_sqs_queue_policy" "karpenter" {
  queue_url = aws_sqs_queue.karpenter.url
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = ["events.amazonaws.com", "sqs.amazonaws.com"] }
      Action    = "sqs:SendMessage"
      Resource  = aws_sqs_queue.karpenter.arn
    }]
  })
}

resource "aws_cloudwatch_event_rule" "karpenter" {
  for_each = {
    spot_interruption   = { source = ["aws.ec2"], detail-type = ["EC2 Spot Instance Interruption Warning"] }
    rebalance           = { source = ["aws.ec2"], detail-type = ["EC2 Instance Rebalance Recommendation"] }
    instance_state      = { source = ["aws.ec2"], detail-type = ["EC2 Instance State-change Notification"] }
    scheduled_change    = { source = ["aws.health"], detail-type = ["AWS Health Event"] }
  }
  name          = "${var.cluster_name}-karpenter-${each.key}"
  event_pattern = jsonencode({ source = each.value.source, "detail-type" = each.value["detail-type"] })
}

resource "aws_cloudwatch_event_target" "karpenter" {
  for_each  = aws_cloudwatch_event_rule.karpenter
  rule      = each.value.name
  target_id = "KarpenterInterruptionQueue"
  arn       = aws_sqs_queue.karpenter.arn
}

# --- Karpenter controller IRSA role + policy -------------------------------
data "aws_iam_policy_document" "karpenter_controller_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_sub}:sub"
      values   = ["system:serviceaccount:kube-system:karpenter"]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_sub}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "karpenter_controller" {
  name               = "${var.cluster_name}-karpenter-controller"
  assume_role_policy = data.aws_iam_policy_document.karpenter_controller_assume.json
}

resource "aws_iam_policy" "karpenter_controller" {
  name = "${var.cluster_name}-karpenter-controller"
  policy = templatefile("${path.module}/policies/karpenter-controller-policy.json.tpl", {
    region       = var.region
    account_id   = local.account_id
    cluster_name = var.cluster_name
    node_role    = aws_iam_role.karpenter_node.arn
    queue_arn    = aws_sqs_queue.karpenter.arn
  })
}

resource "aws_iam_role_policy_attachment" "karpenter_controller" {
  role       = aws_iam_role.karpenter_controller.name
  policy_arn = aws_iam_policy.karpenter_controller.arn
}

# --- Karpenter controller (Helm, from the public ECR OCI registry) ---------
resource "helm_release" "karpenter" {
  name       = "karpenter"
  repository = "oci://public.ecr.aws/karpenter"
  chart      = "karpenter"
  version    = var.karpenter_chart_version
  namespace  = "kube-system"

  set {
    name  = "settings.clusterName"
    value = var.cluster_name
  }
  set {
    name  = "settings.interruptionQueue"
    value = aws_sqs_queue.karpenter.name
  }
  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = aws_iam_role.karpenter_controller.arn
  }
  # Ensure the controller schedules onto the system managed node group.
  set {
    name  = "controller.resources.requests.cpu"
    value = "500m"
  }
  set {
    name  = "controller.resources.requests.memory"
    value = "512Mi"
  }

  depends_on = [
    aws_iam_role_policy_attachment.karpenter_controller,
    aws_eks_access_entry.karpenter_node,
  ]
}

# --- Default NodePool + EC2NodeClass, via a small local Helm chart ----------
# Managed in Terraform (not GitOps) because they need Terraform-computed values
# (node role, discovery tag) and depend on the Karpenter CRDs installed above.
resource "helm_release" "karpenter_resources" {
  name      = "karpenter-resources"
  chart     = "${path.module}/charts/karpenter-resources"
  namespace = "kube-system"

  values = [yamlencode({
    clusterName       = var.cluster_name
    nodeRole          = aws_iam_role.karpenter_node.name
    discoveryTag      = var.cluster_name
    instanceCategories = var.karpenter_instance_categories
    capacityTypes     = var.karpenter_capacity_types
    cpuLimit          = var.karpenter_cpu_limit
  })]

  depends_on = [helm_release.karpenter]
}
