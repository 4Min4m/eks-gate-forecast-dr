data "tls_certificate" "eks" {
  url = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

# KMS: envelope encryption for Kubernetes secrets
data "aws_caller_identity" "current" {}

resource "aws_kms_key" "eks" {
  description             = "Envelope encryption key for EKS ${var.cluster_name} secrets"
  deletion_window_in_days = 10
  enable_key_rotation     = true
  # Explicit key policy (this is what AWS applies by default, written down so
  # it's reviewable): the account's IAM policies govern who may use the key.
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "EnableIAMPolicies"
      Effect    = "Allow"
      Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" }
      Action    = "kms:*"
      Resource  = "*"
    }]
  })
  tags = { Name = "${var.cluster_name}-eks-kms" }
}

resource "aws_kms_alias" "eks" {
  name          = "alias/${var.cluster_name}-eks"
  target_key_id = aws_kms_key.eks.key_id
}

# Cluster IAM role
resource "aws_iam_role" "cluster" {
  name = "${var.cluster_name}-cluster-role"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Action = "sts:AssumeRole", Effect = "Allow", Principal = { Service = "eks.amazonaws.com" } }]
  })
}

resource "aws_iam_role_policy_attachment" "cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.cluster.name
}

resource "aws_iam_role_policy_attachment" "cluster_vpc_resource_controller" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
  role       = aws_iam_role.cluster.name
}

# Control-plane security group
resource "aws_security_group" "cluster" {
  #checkov:skip=CKV_AWS_382:Control-plane ENIs need open egress to reach node kubelets, webhooks and AWS APIs; standard EKS pattern.
  name_prefix = "${var.cluster_name}-cluster-sg"
  description = "Additional security group for the ${var.cluster_name} EKS control plane"
  vpc_id      = var.vpc_id
  ingress {
    description = "Kubernetes API from inside the VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }
  egress {
    description = "Control plane to nodes, webhooks and AWS APIs"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name                     = "${var.cluster_name}-cluster-sg"
    "karpenter.sh/discovery" = var.cluster_name
  }
}

# The cluster
resource "aws_eks_cluster" "main" {
  #checkov:skip=CKV_AWS_39:Public endpoint is kept for operator/CI access but locked to explicit CIDRs (variable validation rejects 0.0.0.0/0).
  name     = var.cluster_name
  role_arn = aws_iam_role.cluster.arn
  version  = var.cluster_version

  # Modern access management (replaces aws-auth ConfigMap).
  access_config {
    authentication_mode = "API_AND_CONFIG_MAP"
  }

  vpc_config {
    subnet_ids              = concat(var.private_subnet_ids, var.public_subnet_ids)
    endpoint_private_access = true
    endpoint_public_access  = var.endpoint_public_access
    public_access_cidrs     = var.endpoint_public_access_cidrs
    security_group_ids      = [aws_security_group.cluster.id]
  }

  encryption_config {
    provider { key_arn = aws_kms_key.eks.arn }
    resources = ["secrets"]
  }

  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  depends_on = [
    aws_iam_role_policy_attachment.cluster_policy,
    aws_iam_role_policy_attachment.cluster_vpc_resource_controller,
  ]
}

# IRSA enablement
resource "aws_iam_openid_connect_provider" "eks" {
  url             = aws_eks_cluster.main.identity[0].oidc[0].issuer
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks.certificates[0].sha1_fingerprint]
  tags            = { Name = "${var.cluster_name}-oidc" }
}

# System node group (runs Karpenter, CoreDNS, controllers)
resource "aws_iam_role" "nodes" {
  name = "${var.cluster_name}-system-node-role"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Action = "sts:AssumeRole", Effect = "Allow", Principal = { Service = "ec2.amazonaws.com" } }]
  })
}

resource "aws_iam_role_policy_attachment" "nodes" {
  for_each = toset([
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
  ])
  policy_arn = each.value
  role       = aws_iam_role.nodes.name
}

resource "aws_eks_node_group" "system" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${var.cluster_name}-system"
  node_role_arn   = aws_iam_role.nodes.arn
  subnet_ids      = var.private_subnet_ids

  scaling_config {
    desired_size = var.system_node_desired_size
    min_size     = var.system_node_min_size
    max_size     = var.system_node_max_size
  }
  update_config { max_unavailable = 1 }

  instance_types = var.system_node_instance_types
  ami_type       = "AL2023_x86_64_STANDARD"
  capacity_type  = "ON_DEMAND"

  labels = { "node-role" = "system" }

  depends_on = [aws_iam_role_policy_attachment.nodes]
  tags       = { Name = "${var.cluster_name}-system-node" }
}

# Karpenter picks node security groups by the karpenter.sh/discovery tag.
# The EKS-managed cluster security group (created by EKS itself, not above)
# is what lets nodes talk to the control plane, to each other and to CoreDNS
# on the system nodes — so Karpenter-launched nodes must get it too. Without
# this tag they'd only get the additional SG above (443 ingress only).
resource "aws_ec2_tag" "cluster_sg_karpenter_discovery" {
  resource_id = aws_eks_cluster.main.vpc_config[0].cluster_security_group_id
  key         = "karpenter.sh/discovery"
  value       = var.cluster_name
}
