# ---------------------------------------------------------------------------
# Network module: VPC, subnets, Internet Gateway, NAT gateway(s) and routing.
#
# Layout (default vpc_cidr = 10.20.0.0/16):
#   public A/B : 10.20.1.0/24  / 10.20.2.0/24   -> ALB
#   app    A/B : 10.20.11.0/24 / 10.20.12.0/24  -> EC2, egress through NAT
#   db     A/B : 10.20.21.0/24 / 10.20.22.0/24  -> RDS, NO route to Internet
#
# Subnets are created with for_each over maps, so adding an AZ is a one-line
# change and resource addresses stay stable.
# ---------------------------------------------------------------------------

data "aws_availability_zones" "available" {
  state = "available"

  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

locals {
  # The platform spans exactly two Availability Zones.
  azs = slice(data.aws_availability_zones.available.names, 0, 2)

  public_subnets = {
    "public-a" = { cidr = cidrsubnet(var.vpc_cidr, 8, 1), az = local.azs[0], tier = "public" }
    "public-b" = { cidr = cidrsubnet(var.vpc_cidr, 8, 2), az = local.azs[1], tier = "public" }
  }

  app_subnets = {
    "app-a" = { cidr = cidrsubnet(var.vpc_cidr, 8, 11), az = local.azs[0], tier = "app" }
    "app-b" = { cidr = cidrsubnet(var.vpc_cidr, 8, 12), az = local.azs[1], tier = "app" }
  }

  db_subnets = {
    "db-a" = { cidr = cidrsubnet(var.vpc_cidr, 8, 21), az = local.azs[0], tier = "db" }
    "db-b" = { cidr = cidrsubnet(var.vpc_cidr, 8, 22), az = local.azs[1], tier = "db" }
  }

  # Single map driving the aws_subnet for_each.
  all_subnets = merge(local.public_subnets, local.app_subnets, local.db_subnets)

  # NAT gateways: one shared (cheap) or one per AZ (HA).
  nat_gateways = var.single_nat_gateway ? {
    "nat-a" = "public-a"
    } : {
    "nat-a" = "public-a"
    "nat-b" = "public-b"
  }

  # Which NAT gateway each app subnet uses for its default route.
  app_nat_targets = {
    "app-a" = "nat-a"
    "app-b" = var.single_nat_gateway ? "nat-a" : "nat-b"
  }
}

# ---------------------------------------------------------------------------
# VPC and subnets
# ---------------------------------------------------------------------------
resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(var.tags, { Name = "${var.name_prefix}-vpc" })
}

resource "aws_subnet" "this" {
  for_each = local.all_subnets

  vpc_id                  = aws_vpc.this.id
  cidr_block              = each.value.cidr
  availability_zone       = each.value.az
  map_public_ip_on_launch = each.value.tier == "public"

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-${each.key}"
    Tier = each.value.tier
  })
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, { Name = "${var.name_prefix}-igw" })
}

# ---------------------------------------------------------------------------
# Public routing (Internet Gateway)
# ---------------------------------------------------------------------------
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, { Name = "${var.name_prefix}-rt-public" })
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "public" {
  for_each = local.public_subnets

  subnet_id      = aws_subnet.this[each.key].id
  route_table_id = aws_route_table.public.id
}

# ---------------------------------------------------------------------------
# NAT gateway(s): outbound-only Internet access for the app subnets
# ---------------------------------------------------------------------------
resource "aws_eip" "nat" {
  for_each = local.nat_gateways

  domain = "vpc"

  tags = merge(var.tags, { Name = "${var.name_prefix}-${each.key}-eip" })
}

resource "aws_nat_gateway" "this" {
  for_each = local.nat_gateways

  allocation_id = aws_eip.nat[each.key].id
  subnet_id     = aws_subnet.this[each.value].id

  tags = merge(var.tags, { Name = "${var.name_prefix}-${each.key}" })

  depends_on = [aws_internet_gateway.this]
}

# ---------------------------------------------------------------------------
# App routing (default route through the NAT gateway)
# ---------------------------------------------------------------------------
resource "aws_route_table" "app" {
  for_each = local.app_subnets

  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, { Name = "${var.name_prefix}-rt-${each.key}" })
}

resource "aws_route" "app_nat" {
  for_each = local.app_subnets

  route_table_id         = aws_route_table.app[each.key].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this[local.app_nat_targets[each.key]].id
}

resource "aws_route_table_association" "app" {
  for_each = local.app_subnets

  subnet_id      = aws_subnet.this[each.key].id
  route_table_id = aws_route_table.app[each.key].id
}

# ---------------------------------------------------------------------------
# DB routing: NO route to the Internet (only the implicit local route).
# This is intentional: the database must never reach or be reached from the
# Internet, even indirectly.
# ---------------------------------------------------------------------------
resource "aws_route_table" "db" {
  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, { Name = "${var.name_prefix}-rt-db" })
}

resource "aws_route_table_association" "db" {
  for_each = local.db_subnets

  subnet_id      = aws_subnet.this[each.key].id
  route_table_id = aws_route_table.db.id
}
