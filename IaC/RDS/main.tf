terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "eu-west-2"
}

# Random suffix for uniqueness on every run
resource "random_pet" "suffix" {
  length = 2
}

# SQL password
resource "random_password" "password" {
  length  = 16
  special = false
}

# -----------------------------------------------------
# VPC (DNS enabled for RDS)
# -----------------------------------------------------
resource "aws_vpc" "sql_vpc" {
  cidr_block           = "10.1.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "sql-vpc-${random_pet.suffix.id}"
  }
}

# Subnet A
resource "aws_subnet" "subnet_1" {
  vpc_id                  = aws_vpc.sql_vpc.id
  cidr_block              = "10.1.1.0/24"
  availability_zone       = "eu-west-2a"
  map_public_ip_on_launch = true

  tags = {
    Name = "sql-subnet-a-${random_pet.suffix.id}"
  }
}

# Subnet B
resource "aws_subnet" "subnet_2" {
  vpc_id                  = aws_vpc.sql_vpc.id
  cidr_block              = "10.1.2.0/24"
  availability_zone       = "eu-west-2b"
  map_public_ip_on_launch = true

  tags = {
    Name = "sql-subnet-b-${random_pet.suffix.id}"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.sql_vpc.id
}

# Route Table
resource "aws_route_table" "rt" {
  vpc_id = aws_vpc.sql_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }
}

resource "aws_route_table_association" "rt_a" {
  subnet_id      = aws_subnet.subnet_1.id
  route_table_id = aws_route_table.rt.id
}

resource "aws_route_table_association" "rt_b" {
  subnet_id      = aws_subnet.subnet_2.id
  route_table_id = aws_route_table.rt.id
}

# -----------------------------------------------------
# Security Group (Open to all temporarily)
# -----------------------------------------------------
resource "aws_security_group" "rds_sg" {
  name        = "rds-sg-${random_pet.suffix.id}"
  description = "Temporary public SQL access for demo"

  vpc_id = aws_vpc.sql_vpc.id

  ingress {
    description = "SQL Server"
    from_port   = 1433
    to_port     = 1433
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # TEMP open inbound for Octopus workers
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "rds-sg-${random_pet.suffix.id}"
  }
}

# -----------------------------------------------------
# Subnet Group
# -----------------------------------------------------
resource "aws_db_subnet_group" "sql_subnets" {
  name       = "sql-subnets-${random_pet.suffix.id}"
  subnet_ids = [
    aws_subnet.subnet_1.id,
    aws_subnet.subnet_2.id
  ]

  tags = {
    Name = "sql-subnets-${random_pet.suffix.id}"
  }
}

# -----------------------------------------------------
# RDS SQL Server (Free Tier)
# -----------------------------------------------------
resource "aws_db_instance" "sqlserver" {
  identifier              = "sql-${random_pet.suffix.id}"
  allocated_storage       = 20
  engine                  = "sqlserver-ex"
  instance_class          = "db.t3.micro"

  # Must be valid (SQL does not allow hyphens)
  username = "admin_${replace(random_pet.suffix.id, "-", "_")}"

  password               = random_password.password.result
  port                   = 1433
  publicly_accessible    = true
  skip_final_snapshot    = true

  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  db_subnet_group_name   = aws_db_subnet_group.sql_subnets.name

  tags = {
    Name = "sql-${random_pet.suffix.id}"
  }
}

# -----------------------------------------------------
# Outputs
# -----------------------------------------------------
output "rds_host" {
  value = aws_db_instance.sqlserver.address
}

output "rds_port" {
  value = aws_db_instance.sqlserver.port
}

output "username" {
  value = aws_db_instance.sqlserver.username
}

output "password" {
  value     = nonsensitive(random_password.password.result)
  sensitive = false
}

output "instance_identifier" {
  value = aws_db_instance.sqlserver.identifier
}
