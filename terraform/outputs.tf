locals {
  has_vpc_flow = length(module.vpc_flow) > 0
  has_nlb      = length(module.nlb) > 0
}

output "scenario" {
  description = "Selected fixture scenario."
  value       = var.scenario
}

output "region" {
  description = "Region where primary resources are deployed."
  value       = var.region
}

output "zone" {
  description = "Zone used for zonal resources."
  value       = var.zone
}

output "mig_name" {
  description = "Managed instance group name for the VPC flow scenario."
  value       = local.has_vpc_flow ? module.vpc_flow[0].mig_name : null
}

output "subnet_name" {
  description = "Subnet used for log filtering."
  value       = local.has_vpc_flow ? module.vpc_flow[0].subnet_name : local.has_nlb ? module.nlb[0].subnet_name : null
}

output "backend_mig_name" {
  description = "Backend managed instance group name for the NLB flow scenario."
  value       = local.has_nlb ? module.nlb[0].backend_mig_name : null
}

output "client_instance_name" {
  description = "Client VM name for the NLB flow scenario."
  value       = local.has_nlb ? module.nlb[0].client_instance_name : null
}

output "forwarding_rule_name" {
  description = "Network load balancer forwarding rule name."
  value       = local.has_nlb ? module.nlb[0].forwarding_rule_name : null
}

output "forwarding_rule_ip" {
  description = "External IP assigned to the network load balancer."
  value       = local.has_nlb ? module.nlb[0].forwarding_rule_ip : null
}

output "backend_service_name" {
  description = "Backend service name for the network load balancer."
  value       = local.has_nlb ? module.nlb[0].backend_service_name : null
}

