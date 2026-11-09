# Module: vpc
# VPC, public subnets, IGW, route table, baseline security groups (E-2: PETPLAT-6, PETPLAT-8)
#
# All-public subnet design (ADR-0001): no NAT Gateway, no private subnets, no VPC
# endpoints. Security groups are the perimeter. See docs/technical-spec.md#vpc-network-design.

locals {
  name_prefix  = "${var.project}-${var.environment}"
  cluster_name = coalesce(var.cluster_name, local.name_prefix)

  tags = merge(
    var.tags,
    {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "terraform"
    },
  )
}

################################################################################
# VPC
################################################################################

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-vpc"
  })
}

# Lock down the default security group: no ingress, no egress.
# Nothing should use it; all resources attach the explicit SGs below.
resource "aws_default_security_group" "this" {
  vpc_id = aws_vpc.this.id

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-default-sg-restricted"
  })
}

################################################################################
# Internet Gateway
################################################################################

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-igw"
  })
}

################################################################################
# Public subnets (no NAT Gateway, no private subnets — intentional, ADR-0001)
################################################################################

resource "aws_subnet" "public" {
  #checkov:skip=CKV_AWS_130:All-public subnet design by ADR-0001; SGs are the perimeter
  count = length(var.public_subnet_cidrs)

  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = merge(local.tags, {
    Name                                          = "${local.name_prefix}-public-${var.availability_zones[count.index]}"
    Tier                                          = "public"
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
    "kubernetes.io/role/elb"                      = "1"
  })

  lifecycle {
    precondition {
      condition     = length(var.public_subnet_cidrs) == length(var.availability_zones)
      error_message = "public_subnet_cidrs and availability_zones must have the same length."
    }
  }
}

################################################################################
# Route table: 0.0.0.0/0 -> IGW
################################################################################

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-public-rt"
  })
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "public" {
  count = length(aws_subnet.public)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}
