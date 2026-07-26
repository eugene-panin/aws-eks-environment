resource "aws_cloudwatch_log_group" "eks" {
  name              = "/aws/eks/${local.cluster_name}/cluster"
  retention_in_days = 30

  tags = local.common_tags
}

resource "aws_eks_cluster" "this" {
  name     = local.cluster_name
  role_arn = aws_iam_role.eks_cluster.arn
  version  = var.cluster_version

  access_config {
    authentication_mode                         = "API"
    bootstrap_cluster_creator_admin_permissions = var.enable_cluster_creator_admin
  }

  enabled_cluster_log_types = [
    "api",
    "audit",
    "authenticator",
    "controllerManager",
    "scheduler",
  ]

  vpc_config {
    endpoint_private_access = true
    endpoint_public_access  = length(var.cluster_endpoint_public_access_cidrs) > 0
    public_access_cidrs     = length(var.cluster_endpoint_public_access_cidrs) > 0 ? var.cluster_endpoint_public_access_cidrs : null
    subnet_ids              = [for subnet in aws_subnet.private : subnet.id]
  }

  depends_on = [
    aws_cloudwatch_log_group.eks,
    aws_iam_role_policy_attachment.eks_cluster,
  ]

  tags = local.common_tags
}

resource "aws_eks_access_entry" "admin" {
  cluster_name  = aws_eks_cluster.this.name
  principal_arn = var.admin_principal_arn
  type          = "STANDARD"

  tags = local.common_tags
}

resource "aws_eks_access_policy_association" "admin" {
  cluster_name  = aws_eks_cluster.this.name
  principal_arn = aws_eks_access_entry.admin.principal_arn
  policy_arn    = "arn:${data.aws_partition.current.partition}:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }
}

resource "aws_vpc_security_group_ingress_rule" "eks_api_private" {
  for_each = local.cluster_private_access_cidrs

  security_group_id = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
  description       = "HTTPS to the private EKS API from ${each.value}"
  cidr_ipv4         = each.value
  from_port         = 443
  ip_protocol       = "tcp"
  to_port           = 443
}

data "aws_eks_addon_version" "selected" {
  for_each = toset([
    "coredns",
    "eks-pod-identity-agent",
    "kube-proxy",
    "vpc-cni",
  ])

  addon_name         = each.value
  kubernetes_version = var.cluster_version
  most_recent        = true
}

resource "aws_eks_addon" "pod_identity_agent" {
  addon_name    = "eks-pod-identity-agent"
  addon_version = data.aws_eks_addon_version.selected["eks-pod-identity-agent"].version
  cluster_name  = aws_eks_cluster.this.name

  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = local.common_tags
}

resource "aws_eks_addon" "vpc_cni" {
  addon_name    = "vpc-cni"
  addon_version = data.aws_eks_addon_version.selected["vpc-cni"].version
  cluster_name  = aws_eks_cluster.this.name

  pod_identity_association {
    role_arn        = aws_iam_role.vpc_cni.arn
    service_account = "aws-node"
  }

  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [
    aws_eks_addon.pod_identity_agent,
    aws_iam_role_policy_attachment.vpc_cni,
  ]

  tags = local.common_tags
}

resource "aws_launch_template" "eks_node" {
  name_prefix            = "${local.cluster_name}-node-"
  update_default_version = true

  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      delete_on_termination = true
      encrypted             = true
      volume_size           = 50
      volume_type           = "gp3"
    }
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_put_response_hop_limit = 1
    http_tokens                 = "required"
    instance_metadata_tags      = "disabled"
  }

  tag_specifications {
    resource_type = "instance"
    tags = merge(local.common_tags, {
      Name = "${local.cluster_name}-node"
    })
  }

  tag_specifications {
    resource_type = "volume"
    tags          = local.common_tags
  }

  tags = local.common_tags
}

resource "aws_eks_node_group" "this" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "${local.name_prefix}-general"
  node_role_arn   = aws_iam_role.eks_node.arn
  subnet_ids      = [for subnet in aws_subnet.private : subnet.id]
  version         = var.cluster_version

  ami_type       = "AL2023_x86_64_STANDARD"
  capacity_type  = "ON_DEMAND"
  instance_types = var.node_instance_types

  launch_template {
    id      = aws_launch_template.eks_node.id
    version = aws_launch_template.eks_node.latest_version
  }

  scaling_config {
    desired_size = var.node_desired_size
    max_size     = var.node_max_size
    min_size     = var.node_min_size
  }

  update_config {
    max_unavailable_percentage = 25
  }

  depends_on = [
    aws_eks_addon.vpc_cni,
    aws_iam_role_policy_attachment.eks_node,
  ]

  lifecycle {
    precondition {
      condition = (
        var.node_min_size <= var.node_desired_size
        && var.node_desired_size <= var.node_max_size
      )
      error_message = "Node group sizes must satisfy min <= desired <= max."
    }
  }

  tags = local.common_tags
}

resource "aws_eks_addon" "node_services" {
  for_each = toset([
    "coredns",
    "kube-proxy",
  ])

  addon_name    = each.value
  addon_version = data.aws_eks_addon_version.selected[each.value].version
  cluster_name  = aws_eks_cluster.this.name

  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [aws_eks_node_group.this]

  tags = local.common_tags
}
