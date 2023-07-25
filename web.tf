resource "aws_vpc" "vpc" {
  cidr_block = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support = true
  tags = {
    "Name" = "dev"
  }
}

data "aws_availability_zones" "available" {}

resource "aws_subnet" "public" {
  availability_zone = data.aws_availability_zones.available.names[0]
  cidr_block = "10.0.1.0/24"
  vpc_id = aws_vpc.vpc.id
  tags = {
    "Name" = "dev_public_subnet"
  }
}

resource "tls_private_key" "ssh" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "ssh" {
  key_name = "dev_keypair"
  public_key = tls_private_key.ssh.public_key_openssh
}

output "ssh_private_key_pem" {
  value = tls_private_key.ssh.private_key_pem
  sensitive = true
}

output "ssh_public_key_pem" {
  value = tls_private_key.ssh.public_key_pem
}

resource "aws_security_group" "securitygroup" {
  description = "Allow in SSH, allow ALL out"
  vpc_id = aws_vpc.vpc.id
  ingress {
    cidr_blocks = ["0.0.0.0/0"]
    from_port = 22
    to_port = 22
    protocol = "tcp"
  }
  egress {
    cidr_blocks = ["0.0.0.0/0"]
    from_port = 0
    to_port = 0
    protocol = "-1"
  }
  tags = {
    "Name" = "allow_ssh"
  }
}

resource "aws_instance" "web-ec2" {
  instance_type = "t2.micro"
  ami = "ami-08541bb85074a743a" # Amazon Linux 2
  subnet_id = aws_subnet.private.id
  security_groups = [aws_security_group.securitygroup.id]
  key_name = aws_key_pair.ssh.key_name
  # disable_api_termination = false
  ebs_optimized = false
  root_block_device {
    volume_size = "10"
  }
  tags = {
    "Name" = "web-ec2"
  }
}

output "instance_private_ip" {
  value = aws_instance.web-ec2.private_ip
}

resource "aws_subnet" "private" {
  availability_zone = data.aws_availability_zones.available.names[0]
  cidr_block = "10.0.2.0/24"
  vpc_id = aws_vpc.vpc.id
  tags = {
    "Name" = "dev_private_subnet"
  }
}

resource "aws_internet_gateway" "internet_gateway" {
  vpc_id = aws_vpc.vpc.id
  tags = {
    "Name" = "dev_internet_gateway"
  }
}

resource "aws_route_table" "internet_gateway" {
  vpc_id = aws_vpc.vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.internet_gateway.id
  }
  tags = {
    Name = "dev_public_rt"
  }
}

resource "aws_route_table_association" "internet_gateway" {
  subnet_id = aws_subnet.public.id
  route_table_id = aws_route_table.internet_gateway.id
}

resource "aws_eip" "nat_gateway" {
  domain = "vpc"

  tags = {
    Name = "nat_eip"
  }
}

resource "aws_nat_gateway" "nat_gateway" {
  allocation_id = aws_eip.nat_gateway.id
  subnet_id = aws_subnet.public.id
  tags = {
    "Name" = "dev_nat_gateway"
  }
}

output "nat_gateway_ip" {
  value = aws_eip.nat_gateway.public_ip
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_gateway.id
  }
  tags = {
    Name = "dev_private_rt"
  }
}

resource "aws_route_table_association" "private" {
  subnet_id = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}

resource "aws_instance" "ec2jumphost" {
  instance_type = "t2.micro"
  ami = "ami-08541bb85074a743a" # https://cloud-images.ubuntu.com/locator/ec2/ (Ubuntu)
  subnet_id = aws_subnet.public.id
  security_groups = [aws_security_group.securitygroup.id]
  key_name = aws_key_pair.ssh.key_name
  disable_api_termination = false
  ebs_optimized = false
  root_block_device {
    volume_size = "10"
  }
  tags = {
    "Name" = "dev-jumphost"
  }
}

resource "aws_eip" "jumphost" {
  instance = aws_instance.ec2jumphost.id
  domain = "vpc"

  tags = {
    Name = "dev-jumphost"
  }
}

output "jumphost_ip" {
  value = aws_eip.jumphost.public_ip
}
