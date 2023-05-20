output "cloud_router_circuit_id" {
  value       = packetfabric_cloud_router.cr.id
  description = "PacketFabric Cloud Router Circuit ID"
}

output "cloud_router_connection_aws_primary" {
  value       = module.aws.cloud_router_connection_aws_primary
  description = "Primary PacketFabric AWS Cloud Router Connection"
}

output "cloud_router_connection_aws_secondary" {
  value       = module.aws.cloud_router_connection_aws_secondary
  description = "Secondary PacketFabric AWS Cloud Router Connection (if redundant is true)"
}

output "cloud_router_connection_google_primary" {
  value       = module.google.cloud_router_connection_google_primary
  description = "Primary PacketFabric Google Cloud Router Connection"
}

output "cloud_router_connection_google_secondary" {
  value       = module.google.cloud_router_connection_google_secondary
  description = "Secondary PacketFabric Google Cloud Router Connection (if redundant is true)"
}

output "cloud_router_connection_azure_primary" {
  value       = module.google.cloud_router_connection_azure_primary
  description = "Primary PacketFabric Azure Cloud Router Connection"
}

output "cloud_router_connection_azure_secondary" {
  value       = module.google.cloud_router_connection_azure_secondary
  description = "Secondary PacketFabric Azure Cloud Router Connection (if redundant is true)"
}
