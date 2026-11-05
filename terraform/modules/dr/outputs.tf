output "primary_endpoint" {
  value       = var.enable_dr_poc ? "https://${local.primary_domain}/dr-check" : null
  description = "Call this directly (curl / Postman) to test the primary region without going through DNS."
}

output "secondary_endpoint" {
  value       = var.enable_dr_poc ? "https://${local.secondary_domain}/dr-check" : null
  description = "Call this directly to test the secondary region."
}

output "failover_endpoint" {
  value       = local.create_dns_record ? "https://${local.failover_fqdn}/dr-check" : "no hosted_zone_id set — DNS-level failover record was skipped, test the two endpoints directly"
  description = "The name clients use; Route 53 answers with the primary or secondary region depending on health."
}

output "table_name" {
  value = var.enable_dr_poc ? aws_dynamodb_table.dr_state[0].name : null
}
