resource "aws_security_group" "ingress_all" {
  provider = aws
  name     = random_pet.name.id
  vpc_id   = aws_vpc.vpc.id
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["${var.my_ip}"]
  }
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 8089
    to_port     = 8089
    protocol    = "tcp"
    cidr_blocks = ["${var.my_ip}"]
  }
  ingress {
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  // Terraform removes the default rule
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "${random_pet.name.id}"
  }
}

# Create the Key Pair
resource "aws_key_pair" "ssh_key" {
  provider   = aws
  key_name   = "ssh_key-${random_pet.name.id}"
  public_key = var.public_key
  tags = {
    Name = "${random_pet.name.id}"
  }
}

# Create NIC for the EC2 instances
resource "aws_network_interface" "nic1" {
  provider        = aws
  subnet_id       = aws_subnet.subnet.id
  security_groups = ["${aws_security_group.ingress_all.id}"]
  tags = {
    Name = "${random_pet.name.id}1"
  }
}

# Create the Ubuntu EC2 instances
resource "aws_instance" "ec2_instance" {
  provider      = aws
  ami           = var.ec2_ami
  instance_type = var.ec2_instance_type
  network_interface {
    network_interface_id = aws_network_interface.nic1.id
    device_index         = 0
  }
  key_name  = aws_key_pair.ssh_key.id
  user_data = file("user-data-ubuntu.sh")
  tags = {
    Name = "${random_pet.name.id}1"
  }
}

# Assign a public IP to EC2 instance 1
resource "aws_eip" "public_ip" {
  provider = aws
  instance = aws_instance.ec2_instance.id
  vpc      = true
  tags = {
    Name = "${random_pet.name.id}1"
  }
}

# Private IPs of the demo Ubuntu instances
output "aws_ec2_private_ip" {
  description = "Private ip address for EC2 instance"
  value       = aws_instance.ec2_instance.private_ip
}

# Public IPs of the demo Ubuntu instances
output "aws_ec2_public_ip" {
  description = "Elastic ip address for EC2 instance (ssh user: ubuntu)"
  value       = aws_eip.public_ip.public_ip
}