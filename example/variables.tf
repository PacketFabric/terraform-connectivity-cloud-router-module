## General VARs
variable "public_key" {
  type        = string
  description = "Public Key used to access demo Virtual Machines."
  sensitive   = true
}
variable "my_ip" {
  type        = string
  description = "Source Public IP for AWS/Google security groups."
  default     = "1.2.3.4/32"
}

## AWS VARs
variable "aws_region" {
  type        = string
  description = "AWS region"
  default     = "us-east-1"
}
variable "aws_pop" {
  type        = string
  description = "PacketFabric AWS pop"
  default     = "WDC2"
}
variable "aws_vpc_cidr" {
  type        = string
  description = "CIDR for the VPC in AWS"
  default     = "10.1.0.0/16"
}
# Subnet Variables
variable "aws_subnet_cidr" {
  type        = string
  description = "CIDR for the subnet in AWS"
  default     = "10.1.1.0/24" # do not use 172.17.0.1/16, internal network used for docker containers used in the demo VMs
}
# Make sure you setup the correct AMI if you chance default AWS region
variable "ec2_ami" {
  description = "Ubuntu 22.04 in aws_region (e.g. us-east-1)"
  default     = "ami-052efd3df9dad4825"
}
variable "ec2_instance_type" {
  description = "Instance Type/Size"
  default     = "t2.micro" # Free tier
}

## Google VARs
variable "gcp_project_id" {
  type        = string
  description = "Google Cloud project ID"
}
variable "google_region" {
  type        = string
  description = "Google region"
  default     = "us-west1"
}
variable "google_zone" {
  type        = string
  description = "Google zone"
  default     = "us-west1-a"
}
variable "google_subnet_cidr" {
  type        = string
  description = "CIDR for the subnet"
  default     = "10.2.1.0/24" # do not use 172.17.0.1/16, internal network used for docker containers used in the demo VMs
}
variable "google_pop" {
  type        = string
  description = "PacketFabric Google pop"
  default     = "PDX2"
}

## Azure VARs
variable "azure_region" {
  type        = string
  description = "Azure region"
  default     = "East US"
}
variable "azure_resource_group" {
  type        = string
  description = "Azure Resource Group"
  default     = "default"
}
variable "azure_pop" {
  type        = string
  description = "PacketFabric Azure pop"
  default     = "New York"
}
variable "azure_vnet_cidr" {
  type        = string
  description = "CIDR for the VNET"
  default     = "10.3.0.0/16" # do not use 172.17.0.1/16, internal network used for docker containers used in the demo VMs
}
variable "azure_subnet_cidr" {
  type        = string
  description = "CIDR for the subnet"
  default     = "10.3.1.0/24"
}
variable "azure_subnet_cidr_gw" {
  type        = string
  description = "CIDR for the gateway subnet"
  default     = "10.3.2.0/24"
}
variable "azure_subscription_id" {
  type        = string
  description = "Azure Subscription ID"
  default     = "0000000-0000000-0000000"
}