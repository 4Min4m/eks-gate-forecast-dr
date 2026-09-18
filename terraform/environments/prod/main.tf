module "network" {
  source             = "../../modules/network"
  cluster_name       = var.cluster_name
  vpc_cidr           = var.vpc_cidr
  az_count           = var.az_count
  single_nat_gateway = var.single_nat_gateway
}

module "eks" {
  source                       = "../../modules/eks"
  cluster_name                 = var.cluster_name
  cluster_version              = var.cluster_version
  vpc_id                       = module.network.vpc_id
  vpc_cidr                     = module.network.vpc_cidr
  private_subnet_ids           = module.network.private_subnet_ids
  public_subnet_ids            = module.network.public_subnet_ids
  endpoint_public_access       = var.endpoint_public_access
  endpoint_public_access_cidrs = var.endpoint_public_access_cidrs
  system_node_instance_types   = var.system_node_instance_types
  system_node_desired_size     = var.system_node_desired_size
  system_node_min_size         = var.system_node_min_size
  system_node_max_size         = var.system_node_max_size
}

module "platform" {
  source                        = "../../modules/platform"
  cluster_name                  = module.eks.cluster_name
  cluster_version               = var.cluster_version
  region                        = var.region
  vpc_id                        = module.network.vpc_id
  oidc_provider_arn             = module.eks.oidc_provider_arn
  oidc_issuer_url               = module.eks.oidc_issuer_url
  karpenter_instance_categories = var.karpenter_instance_categories
  karpenter_capacity_types      = var.karpenter_capacity_types
  karpenter_cpu_limit           = var.karpenter_cpu_limit
}
