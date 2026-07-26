output "vpc_id" {
  description = "ID of the VPC containing the EKS environment."
  value       = aws_vpc.this.id
}

output "availability_zones" {
  description = "The three availability zones used by the environment."
  value       = local.availability_zones
}

output "public_subnet_ids" {
  description = "Public subnet IDs keyed by availability zone."
  value       = { for availability_zone, subnet in aws_subnet.public : availability_zone => subnet.id }
}

output "private_subnet_ids" {
  description = "Private EKS worker subnet IDs keyed by availability zone."
  value       = { for availability_zone, subnet in aws_subnet.private : availability_zone => subnet.id }
}

output "data_subnet_ids" {
  description = "Isolated data subnet IDs keyed by availability zone."
  value       = { for availability_zone, subnet in aws_subnet.data : availability_zone => subnet.id }
}

output "nat_gateway_mode" {
  description = "Selected NAT gateway availability mode."
  value       = var.nat_gateway_mode
}
