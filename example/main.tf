# module "packetfabric_cloud_router" {
#   source  = "packetfabric/cloud-router-module/connectivity"
#   version = "0.3.1"
#   name    = random_pet.name.id
#   labels  = ["terraform", "demo"]
#   aws_cloud_router_connections = [
#     {
#       name       = "${random_pet.name.id}-aws-west"
#       aws_region = var.aws_region
#       aws_vpc_id = aws_vpc.vpc.id
#       aws_pop    = var.aws_pop
#       # redundant  = true
#     }
#   ]
#   google_cloud_router_connections = [
#     {
#       name           = "${random_pet.name.id}-google-west"
#       google_project = var.gcp_project_id
#       google_region  = var.google_region
#       google_network = google_compute_network.vpc.name
#       google_pop     = var.google_pop
#       # redundant      = true
#     }
#   ]
#   azure_cloud_router_connections = [
#     {
#       name                  = "${random_pet.name.id}-azure-east"
#       azure_region          = var.azure_region
#       azure_resource_group  = azurerm_resource_group.resource_group.name
#       azure_vnet            = azurerm_virtual_network.virtual_network.name
#       azure_pop             = var.azure_pop
#       # skip_gateway          = true
#       azure_subscription_id = var.azure_subscription_id
#       # redundant             = true
#     }
#   ]
# }
