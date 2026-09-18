output "cluster_name" { value = module.eks.cluster_name }
output "cluster_endpoint" { value = module.eks.cluster_endpoint }
output "vpc_id" { value = module.network.vpc_id }
output "karpenter_node_role" { value = module.platform.karpenter_node_role_name }
