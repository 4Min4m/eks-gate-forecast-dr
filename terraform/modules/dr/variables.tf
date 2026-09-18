variable "enable_dr_poc" {
  type        = bool
  default     = false
  description = <<-EOT
    Master switch for the entire DR proof-of-concept. Defaults to false so
    this never deploys (and never costs anything) by accident. Per PLAN's
    own non-goal, this is meant to be flipped true only for the duration of
    a real failover test, then flipped back and applied again to tear
    everything down — not left running.
  EOT
}

variable "name_prefix" {
  type        = string
  description = "Prefix for all DR resource names, e.g. cluster_name."
}

variable "primary_region" {
  type = string
}

variable "secondary_region" {
  type        = string
  description = "Second AWS region for the DynamoDB Global Table replica and the standby Lambda/API Gateway."
}

variable "hosted_zone_id" {
  type        = string
  default     = ""
  description = <<-EOT
    Route 53 PUBLIC hosted zone ID you own, used for the failover record.
    Left blank by default because not everyone has a domain handy for a
    POC — if blank, DR resources (DynamoDB, Lambda, API Gateways, health
    checks) still deploy, but the Route 53 failover record is skipped.
    You can still test failover by watching the two health checks' status
    directly (see the study guide's Phase 4 exercise) without owning a
    domain, or register a low-cost one and set this before testing the
    full DNS-level failover.
  EOT
}

variable "record_name" {
  type        = string
  default     = "dr-poc"
  description = "Subdomain (relative to the hosted zone) the failover record is created under, e.g. 'dr-poc' -> dr-poc.yourdomain.com."
}

variable "tags" {
  type    = map(string)
  default = {}
}
