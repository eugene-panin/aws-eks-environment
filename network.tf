data "aws_availability_zones" "available" {
  state = "available"

  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = local.name_prefix
  }

  lifecycle {
    precondition {
      condition     = length(data.aws_availability_zones.available.names) >= 3
      error_message = "The selected AWS region must expose at least three standard availability zones."
    }
  }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${local.name_prefix}-igw"
  }
}

resource "aws_subnet" "public" {
  for_each = local.public_subnets

  vpc_id                  = aws_vpc.this.id
  availability_zone       = each.key
  cidr_block              = each.value
  map_public_ip_on_launch = true

  tags = {
    Name                     = "${local.name_prefix}-public-${each.key}"
    "kubernetes.io/role/elb" = "1"
    Tier                     = "public"
  }
}

resource "aws_subnet" "private" {
  for_each = local.private_subnets

  vpc_id                  = aws_vpc.this.id
  availability_zone       = each.key
  cidr_block              = each.value
  map_public_ip_on_launch = false

  tags = {
    Name                                          = "${local.name_prefix}-private-${each.key}"
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
    "kubernetes.io/role/internal-elb"             = "1"
    Tier                                          = "private"
  }
}

resource "aws_subnet" "data" {
  for_each = local.data_subnets

  vpc_id                  = aws_vpc.this.id
  availability_zone       = each.key
  cidr_block              = each.value
  map_public_ip_on_launch = false

  tags = {
    Name = "${local.name_prefix}-data-${each.key}"
    Tier = "data"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${local.name_prefix}-public"
    Tier = "public"
  }
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "public" {
  for_each = aws_subnet.public

  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

resource "aws_eip" "nat" {
  for_each = toset(local.nat_gateway_availability_zones)

  domain = "vpc"

  tags = {
    Name = "${local.name_prefix}-nat-${each.key}"
  }

  depends_on = [aws_internet_gateway.this]
}

resource "aws_nat_gateway" "this" {
  for_each = toset(local.nat_gateway_availability_zones)

  allocation_id = aws_eip.nat[each.key].id
  subnet_id     = aws_subnet.public[each.key].id

  tags = {
    Name = "${local.name_prefix}-nat-${each.key}"
  }

  depends_on = [aws_internet_gateway.this]
}

resource "aws_route_table" "private" {
  for_each = toset(local.availability_zones)

  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${local.name_prefix}-private-${each.key}"
    Tier = "private"
  }
}

resource "aws_route" "private_nat" {
  for_each = toset(local.availability_zones)

  route_table_id         = aws_route_table.private[each.key].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id = aws_nat_gateway.this[
    var.nat_gateway_mode == "one_per_az" ? each.key : local.nat_gateway_availability_zones[0]
  ].id
}

resource "aws_route_table_association" "private" {
  for_each = aws_subnet.private

  subnet_id      = each.value.id
  route_table_id = aws_route_table.private[each.key].id
}

resource "aws_route_table" "data" {
  for_each = toset(local.availability_zones)

  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${local.name_prefix}-data-${each.key}"
    Tier = "data"
  }
}

resource "aws_route_table_association" "data" {
  for_each = aws_subnet.data

  subnet_id      = each.value.id
  route_table_id = aws_route_table.data[each.key].id
}

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids = concat(
    [for route_table in aws_route_table.private : route_table.id],
    [for route_table in aws_route_table.data : route_table.id]
  )

  tags = {
    Name = "${local.name_prefix}-s3"
  }
}
