# PROD — HA and headroom. One NAT per AZ, larger ceiling, on-demand-first.
region       = "us-east-1"
cluster_name = "httpbin-prod"
vpc_cidr     = "10.20.0.0/16"

single_nat_gateway = false # one NAT per AZ for availability

# Lock the API endpoint down to corporate/CI egress ranges only.
endpoint_public_access_cidrs = ["198.51.100.0/24"]

system_node_instance_types = ["m5.large"]
system_node_desired_size   = 3
system_node_min_size       = 3
system_node_max_size       = 5

# Karpenter: on-demand first for stability, higher ceiling, broader families.
karpenter_instance_categories = ["m", "c", "r"]
karpenter_capacity_types      = ["on-demand", "spot"]
karpenter_cpu_limit           = "300"

tags = {
  Project   = "eks-httpbin-alb"
  ManagedBy = "terraform"
  Env       = "prod"
}
