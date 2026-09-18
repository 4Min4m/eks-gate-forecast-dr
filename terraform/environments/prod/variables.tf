variable "region" { type = string }
variable "cluster_name" { type = string }
variable "cluster_version" {
  type    = string
  default = "1.33"
}
variable "vpc_cidr" { type = string }
variable "az_count" {
  type    = number
  default = 2
}
variable "single_nat_gateway" { type = bool }

variable "endpoint_public_access" {
  type    = bool
  default = true
}
variable "endpoint_public_access_cidrs" { type = list(string) }

variable "system_node_instance_types" { type = list(string) }
variable "system_node_desired_size" { type = number }
variable "system_node_min_size" { type = number }
variable "system_node_max_size" { type = number }

variable "karpenter_instance_categories" { type = list(string) }
variable "karpenter_capacity_types" { type = list(string) }
variable "karpenter_cpu_limit" { type = string }

variable "tags" { type = map(string) }
