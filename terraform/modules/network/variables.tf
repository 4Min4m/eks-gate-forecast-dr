variable "cluster_name" {
  type        = string
  description = "Cluster name used for resource naming and discovery tags"
}

variable "vpc_cidr" {
  type        = string
  description = "CIDR block for the VPC"
}

variable "az_count" {
  type        = number
  description = "Number of Availability Zones to spread subnets across"
  default     = 2
}

variable "single_nat_gateway" {
  type        = bool
  description = "true = one shared NAT (cheaper, dev); false = one NAT per AZ (HA, prod)"
  default     = true
}
