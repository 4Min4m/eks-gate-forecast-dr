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

# DR proof-of-concept — disabled by default (var.enable_dr_poc).
# Deliberately independent of the EKS/network modules above: this doesn't
# touch the cluster at all, so it can be applied/destroyed on its own
# without any risk to the running platform.
module "dr" {
  source = "../../modules/dr"
  providers = {
    aws           = aws
    aws.secondary = aws.secondary
  }
  enable_dr_poc    = var.enable_dr_poc
  name_prefix      = var.cluster_name
  primary_region   = var.region
  secondary_region = var.dr_secondary_region
  hosted_zone_id   = var.dr_hosted_zone_id
  record_name      = var.dr_record_name
  tags             = var.tags
}
