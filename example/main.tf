resource "random_pet" "name" {}

module "packetfabric_cloud_router" {
  source  = "packetfabric/cloud-router-module/connectivity"
  version = "0.3.0"
  name    = random_pet.name.id
  labels  = ["terraform", "demo"]
  aws_cloud_router_connections = [
    {
      name       = "${random_pet.name.id}-aws-west"
      aws_region = var.aws_region
      aws_vpc_id = var.aws_vpc_id
      aws_pop    = var.aws_pop
      # redundant  = true
    }
  ]
  google_cloud_router_connections = [
    {
      name           = "${random_pet.name.id}-google-west"
      google_project = var.gcp_project_id
      google_region  = var.google_region
      google_network = var.google_network
      google_pop     = var.google_pop
      # redundant      = true
    }
  ]
  azure_cloud_router_connections = [
    {
      name                 = "${random_pet.name.id}-azure-east"
      azure_region         = var.azure_region
      azure_resource_group = var.azure_resource_group
      azure_vnet           = var.azure_vnet
      azure_pop            = var.azure_pop
      # skip_gateway          = true
      azure_subscription_id = var.azure_subscription_id
      # redundant             = true
    }
  ]
}
