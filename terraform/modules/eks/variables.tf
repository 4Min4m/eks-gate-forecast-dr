variable "cluster_name" { type = string }
variable "cluster_version" { type = string }
variable "vpc_id" { type = string }
variable "vpc_cidr" { type = string }
variable "private_subnet_ids" { type = list(string) }
variable "public_subnet_ids" { type = list(string) }

variable "endpoint_public_access" {
  type    = bool
  default = true
}

variable "endpoint_public_access_cidrs" {
  type        = list(string)
  description = "CIDRs allowed to reach the public API endpoint. Never 0.0.0.0/0."
  validation {
    condition     = !contains(var.endpoint_public_access_cidrs, "0.0.0.0/0")
    error_message = "0.0.0.0/0 is not allowed; scope to specific CIDRs or disable public access."
  }
}

variable "system_node_instance_types" {
  type    = list(string)
  default = ["t3.large"]
}
variable "system_node_desired_size" {
  type    = number
  default = 2
}
variable "system_node_min_size" {
  type    = number
  default = 2
}
variable "system_node_max_size" {
  type    = number
  default = 3
}
