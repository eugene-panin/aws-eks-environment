locals {
  name_prefix  = "${var.project_name}-${var.environment}"
  cluster_name = "${local.name_prefix}-eks"

  common_tags = merge(var.extra_tags, {
    Environment = var.environment
    ManagedBy   = "Terraform"
    Project     = var.project_name
    Repository  = "github.com/eugene-panin/aws-eks-environment"
  })

  availability_zones = slice(
    data.aws_availability_zones.available.names,
    0,
    min(3, length(data.aws_availability_zones.available.names))
  )

  public_subnets = {
    for index, availability_zone in local.availability_zones :
    availability_zone => cidrsubnet(var.vpc_cidr, 4, index)
  }

  private_subnets = {
    for index, availability_zone in local.availability_zones :
    availability_zone => cidrsubnet(var.vpc_cidr, 4, index + 3)
  }

  data_subnets = {
    for index, availability_zone in local.availability_zones :
    availability_zone => cidrsubnet(var.vpc_cidr, 4, index + 6)
  }

  nat_gateway_availability_zones = (
    var.nat_gateway_mode == "one_per_az"
    ? local.availability_zones
    : slice(local.availability_zones, 0, min(1, length(local.availability_zones)))
  )

  cluster_private_access_cidrs = toset(concat(
    [var.vpc_cidr],
    var.cluster_private_access_cidrs
  ))
}
