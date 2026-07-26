output "cluster_name" {
  description = "Name of the EKS cluster."
  value       = aws_eks_cluster.this.name
}

output "cluster_endpoint" {
  description = "Kubernetes API endpoint; private by default with public access available only by explicit CIDR."
  value       = aws_eks_cluster.this.endpoint
}

output "cluster_security_group_id" {
  description = "Security group created by EKS for control-plane and node communication."
  value       = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
}

output "node_group_name" {
  description = "Name of the managed EKS node group."
  value       = aws_eks_node_group.this.node_group_name
}

output "eks_iam_role_arns" {
  description = "IAM roles assumed by the EKS control plane, worker nodes, and VPC CNI."
  value = {
    cluster = aws_iam_role.eks_cluster.arn
    node    = aws_iam_role.eks_node.arn
    vpc_cni = aws_iam_role.vpc_cni.arn
  }
}
