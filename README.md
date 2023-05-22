[![Release](https://img.shields.io/github/v/release/PacketFabric/terraform-connectivity-cloud-router-module?display_name=tag)](https://github.com/PacketFabric/terraform-connectivity-cloud-router-module/releases)
![release-date](https://img.shields.io/github/release-date/PacketFabric/terraform-connectivity-cloud-router-module)
![contributors](https://img.shields.io/github/contributors/PacketFabric/terraform-connectivity-cloud-router-module)
![commit-activity](https://img.shields.io/github/commit-activity/m/PacketFabric/terraform-connectivity-cloud-router-module)
[![License](https://img.shields.io/github/license/PacketFabric/terraform-connectivity-cloud-router-module)](https://github.com/PacketFabric/terraform-connectivity-cloud-router-module)

## PacketFabric Cloud Router module

This Terraform module enables users to seamlessly create, update, and delete [PacketFabric Cloud Router](https://docs.packetfabric.com/cr/), which can be used to connect AWS and Google Cloud networks.

The PacketFabric Cloud Router module simplifies the process of adding or removing connections between public cloud providers through the secure and reliable [PacketFabric's Network-as-a-Service platform](https://packetfabric.com/).

If you would like to see support for other cloud service providers (e.g. Azure, Oracle, IBM, etc.), please open an issue on [GitHub](https://github.com/PacketFabric/terraform-connectivity-cloud-router-module/issues) to share your suggestions or requests.

## Requirements

### Ecosystem Requirements

| Ecosystem | Version |
|-----------|---------|
| [terraform](https://www.terraform.io) | ">= 1.1.0, < 1.3.0" |
<!-- | [terraform](https://www.terraform.io) | ">= 1.3.0" | -->

### Terraform Providers

| Name | Version |
|------|---------|
| [PacketFabric Terraform Provider](https://registry.terraform.io/providers/PacketFabric/packetfabric) | >= 1.6.0 |
| [AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest) | >= 4.62.0 |
| [Google Provider](https://registry.terraform.io/providers/hashicorp/google/latest) | >= 4.61.0 |
| [Azure Provider](https://registry.terraform.io/providers/hashicorp/azurerm/latest) | >= 3.56.0 |

### Before you begin

- Before you begin we recommend you read about the [Terraform basics](https://www.terraform.io/intro)
- Don't have a PacketFabric Account? [Get Started](https://docs.packetfabric.com/intro/)
- Don't have an AWS Account? [Get Started](https://aws.amazon.com/free/)
- Don't have a Google Account? [Get Started](https://cloud.google.com/free)
- Don't have an Azure Account? [Get Started](https://azure.microsoft.com/en-us/free/)

### Prerequisites

Ensure you have installed the following prerequisites:

- [Git](https://git-scm.com/downloads)
- [Terraform](https://learn.hashicorp.com/tutorials/terraform/install-cli)

Ensure you have the following items available:

- [AWS Account ID](https://docs.aws.amazon.com/IAM/latest/UserGuide/console_account-alias.html)
- [AWS Access and Secret Keys](https://docs.aws.amazon.com/general/latest/gr/aws-security-credentials.html)
- [Google Service Account](https://cloud.google.com/compute/docs/access/create-enable-service-accounts-for-instances)
- [Microsoft Azure Service Principal](https://docs.microsoft.com/en-us/azure/developer/terraform/authenticate-to-azure?tabs=bash)
- [PacketFabric Billing Account](https://docs.packetfabric.com/api/examples/account_uuid/)
- [PacketFabric API key](https://docs.packetfabric.com/admin/my_account/keys/)


For Azure, enable AzureExpressRoute in the Azure Subscription
```sh
az feature register --namespace Microsoft.Network --name AllowExpressRoutePorts
az provider register -n Microsoft.Network
```

:warning: **Subnet Overlap Between Cloud Providers**

When using multiple cloud providers, be cautious of potential subnet overlap. Subnet overlap occurs when conflicting IP address ranges are used in different cloud networks.

:warning: **Azure Gateway subnet**

Please ensure that the Virtual Network (VNet) you choose is equipped with a Gateway subnet. This is a critical requirement for setting up a successful connection. For more information, refer to [Microsoft Learn](https://learn.microsoft.com/en-us/azure/expressroute/expressroute-about-virtual-network-gateways#gwsub).

## Setup

1. Make sure you enabled Compute Engine API in Google Cloud
2. Create Google Service Account along wih the Private Key
3. Create an AWS Access Key and Secret Access Key
4. Create an Microsoft Azure Service Principal
4. Create a PacketFabric API Key
5. Gather necessary information such as AWS account ID, Google and AWS regions, VPC name (Google), VPC ID (AWS), VNet (Azure), Resource Group (Azure), Google Project ID and [PacketFabric Cloud On-Ramps](https://packetfabric.com/locations/cloud-on-ramps) (PoP)

Environement variables needed:

```sh
### PacketFabric
export PF_TOKEN="secret"
export PF_ACCOUNT_ID="123456789"
### AWS
export PF_AWS_ACCOUNT_ID="98765432"
export AWS_ACCESS_KEY_ID="ABCDEFGH"
export AWS_SECRET_ACCESS_KEY="secret"
### Google
export GOOGLE_CREDENTIALS='{ "type": "service_account", "project_id": "demo-setting-1234", "private_key_id": "1234", "private_key": "-----BEGIN PRIVATE KEY-----\nsecret\n-----END PRIVATE KEY-----\n", "client_email": "demoapi@demo-setting-1234.iam.gserviceaccount.com", "client_id": "102640829015169383380", "auth_uri": "https://accounts.google.com/o/oauth2/auth", "token_uri": "https://oauth2.googleapis.com/token", "auth_provider_x509_cert_url": "https://www.googleapis.com/oauth2/v1/certs", "client_x509_cert_url": "https://www.googleapis.com/robot/v1/metadata/x509/demoapi%40demo-setting-1234.iam.gserviceaccount.com" }'
### Azure
export ARM_CLIENT_ID="00000000-0000-0000-0000-000000000000"
export ARM_CLIENT_SECRET="00000000-0000-0000-0000-000000000000"
export ARM_SUBSCRIPTION_ID="00000000-0000-0000-0000-000000000000"
export ARM_TENANT_ID="00000000-0000-0000-0000-000000000000"
```

Example with Windows PowerShell:
```powershell
PS C:\> $Env:PF_TOKEN="secret"
PS C:\> $Env:PF_ACCOUNT_ID="123456789"
```

**Note**: To convert a pretty-printed JSON into a single line JSON string: `jq -c '.' google_credentials.json`.

## Example

### Example Cloud Router AWS/Google/Azure usage with single connections (1Gbps)

```hcl
module "packetfabric" {
  source  = "packetfabric/cloud-router-module/connectivity"
  version = "0.3.0"
  name    = "demo-standalone1"
  labels  = ["terraform", "dev"]
  # PacketFabric Cloud Router Connection to Google
  google_cloud_router_connections = [
    {
      name           = "my-google-connection"
      labels         = ["dev"]
      google_project = "prefab-setting-357415"
      google_region  = "us-west1"
      google_network = "myvpc"
      google_pop     = "PDX2" # https://packetfabric.com/locations/cloud-on-ramps
    }
  ]
  # PacketFabric Cloud Router Connection to AWS
  aws_cloud_router_connections = [
    {
      name       = "my-aws-connection"
      labels     = ["dev"]
      aws_region = "us-east-1"
      aws_vpc_id = "vpc-bea401c4"
      aws_pop    = "NYC1" # https://packetfabric.com/locations/cloud-on-ramps
    }
  ]
  # PacketFabric Cloud Router Connection to Azure
  azure_cloud_router_connections = [
    {
      name                  = "my-azure-connection"
      labels                = ["dev"]
      azure_region          = "North Central US"
      azure_resource_group  = "MyResourceGroup"
      azure_vnet            = "MyVnet"
      azure_pop             = "Chicago" # https://docs.microsoft.com/en-us/azure/expressroute/expressroute-locations-providers
      azure_subscription_id = "00000000-0000-0000-0000-000000000000" # same as env var ARM_SUBSCRIPTION_ID
    }
  ]
}
```

### Example Cloud Router AWS/Google/Azure usage with single connections specifying the speed

```hcl
module "packetfabric" {
  source  = "packetfabric/cloud-router-module/connectivity"
  version = "0.3.0"
  name    = "demo-standalone2"
  labels  = ["terraform", "dev"]
  # PacketFabric Cloud Router
  asn      = 4556
  capacity = "10Gbps"
  # PacketFabric Cloud Router Connection to Google
  google_cloud_router_connections = [
    {
      name           = "my-google-connection"
      google_project = "prefab-setting-357415"
      google_region  = "us-west1"
      google_network = "myvpc"
      google_pop     = "PDX2" # https://packetfabric.com/locations/cloud-on-ramps
      google_speed   = "2Gbps"
    }
  ]
  # PacketFabric Cloud Router Connection to AWS
  aws_cloud_router_connections = [
    {
      name       = "my-aws-connection"
      aws_region = "us-east-1"
      aws_vpc_id = "vpc-bea401c4"
      aws_pop    = "NYC1" # https://packetfabric.com/locations/cloud-on-ramps
      aws_speed  = "2Gbps"
    }
  ]
  # PacketFabric Cloud Router Connection to Azure
  azure_cloud_router_connections = [
    {
      name                  = "my-azure-connection"
      labels                = ["dev"]
      azure_region          = "North Central US"
      azure_resource_group  = "MyResourceGroup"
      azure_vnet            = "MyVnet"
      azure_pop             = "Chicago" # https://docs.microsoft.com/en-us/azure/expressroute/expressroute-locations-providers
      azure_subscription_id = "00000000-0000-0000-0000-000000000000" # same as env var ARM_SUBSCRIPTION_ID
      azure_speed           = "2Gbps"
    }
  ]
}
```

### Example Cloud Router AWS/Google usage with redundant connections

```hcl
module "packetfabric" {
  source  = "packetfabric/cloud-router-module/connectivity"
  version = "0.3.0"
  name    = "demo-redundant"
  labels  = ["terraform", "prod"]
  # PacketFabric Cloud Router
  asn      = 4556
  capacity = "10Gbps"
  # PacketFabric Cloud Router Connection to Google
  google_cloud_router_connections = [
    {
      name           = "my-google-connection"
      google_project = "prefab-setting-357415"
      google_region  = "us-west1"
      google_network = "default"
      google_asn     = 16550
      google_pop     = "SFO1" # https://packetfabric.com/locations/cloud-on-ramps
      google_speed   = "1Gbps"
      redundant      = true
      bgp_prefixes = [ # The prefixes in question must already be present as routes within the route table that is associated with the VPC
        {
          prefix = "172.16.1.0/24"
          type   = "out" # Allowed Prefixes to Cloud (to Google)
        }
      ]
    }
  ]
  # PacketFabric Cloud Router Connection to AWS
  aws_cloud_router_connections = [
    {
      name       = "my-aws-connection"
      aws_region = "us-east-1"
      aws_vpc_id = "vpc-bea401c4"
      aws_asn1   = 64512
      aws_asn2   = 64513
      aws_pop    = "WDC1" # https://packetfabric.com/locations/cloud-on-ramps
      aws_speed  = "2Gbps"
      redundant  = true
      bgp_prefixes = [ # The prefixes in question must already be present as routes within the route table that is associated with the VPC
        {
          prefix = "10.1.1.0/24"
          type   = "out" # Allowed Prefixes to Cloud (to AWS)
        }
      ]
    }
  ]
  azure_cloud_router_connections = [
    {
      name                  = "my-azure-connection"
      labels                = ["dev"]
      azure_region          = "North Central US"
      azure_resource_group  = "MyResourceGroup"
      azure_vnet            = "MyVnet"
      azure_pop             = "Chicago" # https://docs.microsoft.com/en-us/azure/expressroute/expressroute-locations-providers
      azure_subscription_id = "00000000-0000-0000-0000-000000000000" # same as env var ARM_SUBSCRIPTION_ID
      azure_speed           = "2Gbps"
      redundant             = true
      bgp_prefixes = [ # The prefixes in question must already be present as routes within the route table that is associated with the VPC
        {
          prefix = "192.168.1.0/24"
          type   = "out" # Allowed Prefixes to Cloud (to Azure)
        }
      ]
    }
  ]
}
```

## Usage

| Input Variable | Required | Default | Description |
|----------------|----------|----------|------------|
| cr_id                     | No      | | The Circuit ID of the PacketFabric Cloud Router (if using an existing one) |
| name                      | No      | | The name of the PacketFabric Cloud Router (if creating a new one) |
| labels                    | No      | terraform | The labels to be assigned to the PacketFabric Cloud Router |
| asn                       | No      | 4556 | The Autonomous System Number (ASN) for the PacketFabric Cloud Router |
| capacity                  | No      | ">100Gbps" | The capacity of the PacketFabric Cloud Router |
| regions                   | No      | ["US"] | The list of regions for the PacketFabric Cloud Router (["US", "UK"]) |
| aws_cloud_router_connections | Yes     | | A list of objects representing the AWS Cloud Router Connections (Private VIF) |
| google_cloud_router_connections | Yes  | | A list of objects representing the Google Cloud Router Connections |
| azure_cloud_router_connections | Yes   | | A list of objects representing the Azure Cloud Router Connections |

**Note**: 

- The default Maximum Transmission Unit (MTU) is set to `1500` in both AWS and Google.
- By default, the BGP prefixes for AWS and Google are configured to use the VPC network as the allowed prefix from/to each cloud.
- To explore pricing options, please visit the [PacketFabric pricing tool](https://packetfabric.com/pricing)
- `name` must follow `^(?:[a-z](?:[-a-z0-9]{0,61}[a-z0-9])?)$`
  - Any lowercase ASCII letter or digit, and possibly hyphen, which should start with a letter and end with a letter or digit, and have at most 63 characters (1 for the starting letter + up to 61 characters in the middle + 1 for the ending letter/digit).

:warning: **AWS and Azure Cloud Router Connection Creation Time**

Please be aware that creating AWS or Azure Cloud Router connections can take up to 30-60 minutes due to the gateway association operation on the CSP side.

### AWS

#### Private VIF

| Input Variable | Required | Default | Description |
|----------------|----------|----------|------------|
| name                      | Yes      | | The name of the PacketFabric Cloud Router Connection and other resources created in AWS |
| labels                    | No       | terraform | If not specified, default to the same labels assigned to the PacketFabric Cloud Router |
| aws_region | Yes | | The AWS region |
| aws_vpc_id | Yes | | The AWS VPC ID<br/>:warning: **must be in the region defined above and makes sure your VPC is not already attached to an existing Virtual Private Gateway**|
| aws_asn1 | No | 64512 | The AWS ASN for the first connection |
| aws_asn2 | No | 64513 | The AWS ASN for the second connection if redundant |
| aws_pop | Yes | | The [PacketFabric Point of Presence](https://packetfabric.com/locations/cloud-on-ramps) for the connection |
| aws_speed | No | 1Gbps | The connection speed |
| redundant | No | false | Create a redundant connection if set to true |
| bgp_prefixes | No | VPC network subnets | List of supplementary [BGP](https://docs.packetfabric.com/cr/bgp/reference/) prefixes - must already exist as established routes in the routing table associated with the VPC |
| bgp_prefixes_match_type | No | exact | The BGP prefixes match type exact or orlonger for all the prefixes |

**Note**: This module currently supports private VIFs only. If you require support for transit or public VIFs, please feel free to open [GitHub Issues](https://github.com/PacketFabric/terraform-connectivity-cloud-router-module/issues) and provide your suggestions or requests.

### Google

| Input Variable | Required | Default | Description |
|----------------|----------|----------|------------|
| name                      | Yes      | | The name of the PacketFabric Cloud Router Connection and other resources created in Google |
| labels                    | No       | terraform | If not specified, default to the same labels assigned to the PacketFabric Cloud Router |
| google_project | Yes | | The Google Cloud project ID |
| google_region | Yes | | The Google Cloud region |
| google_network | Yes | | The Google Cloud VPC network name<br/>:warning: **must be in the region defined above**|
| google_asn | No | 16550 | The Google Cloud ASN |
| google_pop | Yes | | The [PacketFabric Point of Presence](https://packetfabric.com/locations/cloud-on-ramps) for the connection |
| google_speed | No | 1Gbps | The connection speed |
| redundant | No | false | Create a redundant connection if set to true |
| bgp_prefixes | No | VPC network subnets | List of supplementary [BGP](https://docs.packetfabric.com/cr/bgp/reference/) prefixes - must already exist as established routes in the routing table associated with the VPC |
| bgp_prefixes_match_type | No | exact | The BGP prefixes match type exact or orlonger for all the prefixes |

### Azure

#### Private Peering

| Input Variable | Required | Default | Description |
|----------------|----------|----------|------------|
| name                      | Yes      | | The name of the PacketFabric Cloud Router Connection and other resources created in Azure |
| labels                    | No       | terraform | If not specified, default to the same labels assigned to the PacketFabric Cloud Router | |
| azure_resource_group | Yes | | The Azure Resource group |
| azure_region | Yes | | The Azure Cloud region |
| azure_vnet | Yes | | The Azure Cloud VNet name<br/>:warning: **must be in the region defined above**|
| azure_asn |  | 12076 | The Azure Cloud ASN (cannot be changed) |
| azure_pop | Yes | | The [PacketFabric Point of Presence](https://packetfabric.com/locations/cloud-on-ramps) for the connection is defined on the Azure side [Search for PacketFabric](https://docs.microsoft.com/en-us/azure/expressroute/expressroute-locations-providers) |
| azure_speed | No | 1Gbps | The connection speed |
| redundant | No | false | Create a redundant connection if set to true |
| skip_gateway | No | false | Skip virtual network gateway creation if set to true. Follow [instructions](https://docs.packetfabric.com/cr/bgp/bgp_azure/) to create the gateway manually |
| azure_subscription_id | No |  | Only required if skip_gateway set to false |
| bgp_prefixes | No | VPC network subnets | List of supplementary [BGP](https://docs.packetfabric.com/cr/bgp/reference/) prefixes - must already exist as established routes in the routing table associated with the VPC |
| bgp_prefixes_match_type | No | exact | The BGP prefixes match type exact or orlonger for all the prefixes |

:warning: **Azure Gateway subnet**

Please ensure that the Virtual Network (VNet) you choose is equipped with a Gateway subnet. This is a critical requirement for setting up a successful connection. For more information, refer to [Microsoft Learn](https://learn.microsoft.com/en-us/azure/expressroute/expressroute-about-virtual-network-gateways#gwsub).

**Note**: The BGP session for Azure is using the following default prefixes: `169.254.244.40/30` (primary) and `169.254.244.44/30` (secondary). Also Azure SKU Tier is set to `Standard` and SKU Family to `MeterdData` in the ExpressRoute. If you like to be able to customize those, please feel free to open a [GitHub Issue](https://github.com/PacketFabric/terraform-connectivity-cloud-router-module/issues).

### Output Variables

| Name | Description |
|------|-------------|
| cloud_router_circuit_id | PacketFabric Cloud Router Circuit ID |
| cloud_router_connection_aws_primary | Primary PacketFabric AWS Cloud Router Connection(s) (Private VIF) |
| cloud_router_connection_aws_secondary | Secondary PacketFabric AWS Cloud Router Connection(s) (Private VIF) (if redundant is true) |
| cloud_router_connection_google_primary | Primary PacketFabric Google Cloud Router Connection(s) |
| cloud_router_connection_google_secondary | Secondary PacketFabric Google Cloud Router Connection(s) (if redundant is true) |
| cloud_router_connection_azure_primary | Primary PacketFabric Azure Cloud Router Connection(s) |
| cloud_router_connection_azure_secondary | Secondary PacketFabric Azure Cloud Router Connection(s) (if redundant is true) |

## Support Information

This repository is community-supported. Follow instructions below on how to raise issues.

### Filing Issues and Getting Help

If you come across a bug or other issue, use [GitHub Issues](https://github.com/PacketFabric/terraform-connectivity-cloud-router-module/issues) to submit an issue for our team. You can also see the current known issues on that page, which are tagged with a purple Known Issue label.

## Copyright

Copyright 2023 PacketFabric, Inc.

### PacketFabric Contributor License Agreement

Before you start contributing to any project sponsored by PacketFabric, Inc. on GitHub, you will need to sign a Contributor License Agreement (CLA).

If you are signing as an individual, we recommend that you talk to your employer (if applicable) before signing the CLA since some employment agreements may have restrictions on your contributions to other projects. Otherwise by submitting a CLA you represent that you are legally entitled to grant the licenses recited therein.

If your employer has rights to intellectual property that you create, such as your contributions, you represent that you have received permission to make contributions on behalf of that employer, that your employer has waived such rights for your contributions, or that your employer has executed a separate CLA with PacketFabric.

If you are signing on behalf of a company, you represent that you are legally entitled to grant the license recited therein. You represent further that each employee of the entity that submits contributions is authorized to submit such contributions on behalf of the entity pursuant to the CLA.