# DEV — cheaper, smaller. Single NAT, small system nodes, spot-friendly Karpenter.
region       = "us-east-1"
cluster_name = "httpbin-dev"
vpc_cidr     = "10.10.0.0/16"

single_nat_gateway = true # one NAT to save cost in dev

# Restrict to YOUR IP/CIDR. 0.0.0.0/0 is rejected by validation.
endpoint_public_access_cidrs = ["203.0.113.10/32"]

system_node_instance_types = ["t3.large"]
system_node_desired_size   = 2
system_node_min_size       = 2
system_node_max_size       = 3

# Karpenter: prefer spot in dev, modest ceiling.
karpenter_instance_categories = ["t", "m"]
karpenter_capacity_types      = ["spot", "on-demand"]
karpenter_cpu_limit           = "50"

tags = {
  Project   = "eks-httpbin-alb"
  ManagedBy = "terraform"
  Env       = "dev"
}

# DR proof-of-concept (Phase 4) — leave enable_dr_poc = false until you're
# actually running the failover exercise (see the study guide). Flip to
# true, apply, run the test, record your RTO, then flip back to false and
# apply again to tear it all down.
enable_dr_poc       = false
dr_secondary_region = "us-west-2"
dr_hosted_zone_id   = "" # CHANGE-ME: a Route 53 public hosted zone ID you own (optional — see module docs)
dr_record_name      = "dr-poc"
