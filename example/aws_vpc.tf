# Create the VPCs
resource "aws_vpc" "vpc" {
  provider             = aws
  cidr_block           = var.aws_vpc_cidr
  enable_dns_hostnames = true
  tags = {
    Name = "${random_pet.name.id}"
  }
}

# Define the subnets
resource "aws_subnet" "subnet" {
  provider   = aws
  vpc_id     = aws_vpc.vpc.id
  cidr_block = var.aws_subnet_cidr
  tags = {
    Name = "${random_pet.name.id}"
  }
}

# Define the internet gateways
resource "aws_internet_gateway" "gw" {
  provider = aws
  vpc_id   = aws_vpc.vpc.id
  tags = {
    Name = "${random_pet.name.id}"
  }
}

# Define the route table
resource "aws_route_table" "route_table" {
  provider = aws
  vpc_id   = aws_vpc.vpc.id
  # internet gw
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }
  tags = {
    Name = "${random_pet.name.id}"
  }
}

# Assign the route table to the subnet
resource "aws_route_table_association" "route_association" {
  provider       = aws
  subnet_id      = aws_subnet.subnet.id
  route_table_id = aws_route_table.route_table.id
}