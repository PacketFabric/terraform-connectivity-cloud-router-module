output "cloud_router_circuit_id" {
  value = length(packetfabric_cloud_router.cr) > 0 ? packetfabric_cloud_router.cr[0].id : null
  description = "PacketFabric Cloud Router Circuit ID"
}

output "cloud_router_connection_aws1_primary" {
  value       = module.aws1.cloud_router_connection_aws_primary
  description = "Primary PacketFabric AWS Cloud Router Connection 1"
}

output "cloud_router_connection_aws1_secondary" {
  value       = module.aws1.cloud_router_connection_aws_secondary
  description = "Secondary PacketFabric AWS Cloud Router Connection 1 (if redundant is true)"
}

output "cloud_router_connection_aws2_primary" {
  value       = module.aws2.cloud_router_connection_aws_primary
  description = "Primary PacketFabric AWS Cloud Router Connection 2"
}

output "cloud_router_connection_aws2_secondary" {
  value       = module.aws2.cloud_router_connection_aws_secondary
  description = "Secondary PacketFabric AWS Cloud Router Connection 2 (if redundant is true)"
}

output "cloud_router_connection_aws3_primary" {
  value       = module.aws3.cloud_router_connection_aws_primary
  description = "Primary PacketFabric AWS Cloud Router Connection 3"
}

output "cloud_router_connection_aws3_secondary" {
  value       = module.aws3.cloud_router_connection_aws_secondary
  description = "Secondary PacketFabric AWS Cloud Router Connection 3 (if redundant is true)"
}

output "cloud_router_connection_google_primary" {
  value       = module.google.cloud_router_connection_google_primary
  description = "Primary PacketFabric Google Cloud Router Connection(s)"
}

output "cloud_router_connection_google_secondary" {
  value       = module.google.cloud_router_connection_google_secondary
  description = "Secondary PacketFabric Google Cloud Router Connection(s) (if redundant is true)"
}

output "cloud_router_connection_azure_primary" {
  value       = module.azure.cloud_router_connection_azure_primary
  description = "Primary PacketFabric Azure Cloud Router Connection(s)"
}

output "cloud_router_connection_azure_secondary" {
  value       = module.azure.cloud_router_connection_azure_secondary
  description = "Secondary PacketFabric Azure Cloud Router Connection(s) (if redundant is true)"
}
