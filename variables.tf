variable "aws_region" {
  description = "AWS region in which to create the environment."
  type        = string
  default     = "eu-west-1"

  validation {
    condition     = can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]+$", var.aws_region))
    error_message = "aws_region must be a valid AWS region name, for example eu-west-1."
  }
}

variable "expected_aws_account_id" {
  description = "AWS account ID that the provider is allowed to modify."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.expected_aws_account_id))
    error_message = "expected_aws_account_id must contain exactly 12 digits."
  }
}

variable "project_name" {
  description = "Short, lowercase project identifier used in names and tags."
  type        = string
  default     = "aws-eks-environment"

  validation {
    condition = (
      length(var.project_name) >= 3 &&
      length(var.project_name) <= 32 &&
      can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.project_name))
    )
    error_message = "project_name must be 3-32 lowercase alphanumeric or hyphen characters, start with a letter, and end with a letter or number."
  }
}

variable "environment" {
  description = "Deployment environment identifier."
  type        = string
  default     = "dev"

  validation {
    condition = (
      length(var.environment) >= 2 &&
      length(var.environment) <= 12 &&
      can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.environment))
    )
    error_message = "environment must be 2-12 lowercase alphanumeric or hyphen characters, start with a letter, and end with a letter or number."
  }
}

variable "vpc_cidr" {
  description = "IPv4 CIDR for the VPC. A /16 through /24 is required to derive nine subnets."
  type        = string
  default     = "10.40.0.0/16"

  validation {
    condition = (
      can(cidrnetmask(var.vpc_cidr)) &&
      can(regex("^([0-9]{1,3}\\.){3}[0-9]{1,3}/(1[6-9]|2[0-4])$", var.vpc_cidr))
    )
    error_message = "vpc_cidr must be a valid IPv4 CIDR with a prefix between /16 and /24."
  }
}

variable "nat_gateway_mode" {
  description = "NAT topology for private worker subnets: single is cheaper; one_per_az removes the cross-AZ dependency."
  type        = string
  default     = "single"

  validation {
    condition     = contains(["single", "one_per_az"], var.nat_gateway_mode)
    error_message = "nat_gateway_mode must be either single or one_per_az."
  }
}

variable "cluster_version" {
  description = "Kubernetes minor version for the EKS control plane and managed node group."
  type        = string
  default     = "1.35"

  validation {
    condition     = can(regex("^1\\.[0-9]{2}$", var.cluster_version))
    error_message = "cluster_version must be a Kubernetes minor version such as 1.35."
  }
}

variable "admin_principal_arn" {
  description = "IAM role ARN granted EKS cluster-admin access through an access entry."
  type        = string

  validation {
    condition = can(regex(
      "^arn:(aws|aws-us-gov|aws-cn):iam::[0-9]{12}:role/.+$",
      var.admin_principal_arn
    ))
    error_message = "admin_principal_arn must be an IAM role ARN."
  }
}

variable "enable_cluster_creator_admin" {
  description = "Whether the identity creating the EKS cluster receives implicit administrator access."
  type        = bool
  default     = false
}

variable "cluster_endpoint_public_access_cidrs" {
  description = "CIDRs allowed to reach the public EKS API endpoint. Empty keeps the endpoint private-only; unrestricted access is rejected."
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for cidr in var.cluster_endpoint_public_access_cidrs :
      can(cidrnetmask(cidr)) && try(tonumber(split("/", cidr)[1]) >= 8, false)
    ])
    error_message = "Every public endpoint CIDR must be valid IPv4 and no broader than /8; unrestricted /0 forms are rejected."
  }
}

variable "cluster_private_access_cidrs" {
  description = "Additional routed IPv4 CIDRs allowed to reach the private EKS API. The VPC CIDR is always allowed."
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for cidr in var.cluster_private_access_cidrs :
      can(cidrnetmask(cidr)) && try(tonumber(split("/", cidr)[1]) >= 8, false)
    ])
    error_message = "Every private endpoint CIDR must be valid IPv4 and no broader than /8."
  }
}

variable "node_instance_types" {
  description = "EC2 instance types available to the EKS managed node group."
  type        = list(string)
  default     = ["t3.medium"]

  validation {
    condition = (
      length(var.node_instance_types) > 0 &&
      alltrue([for instance_type in var.node_instance_types : length(trimspace(instance_type)) > 0])
    )
    error_message = "node_instance_types must contain at least one non-empty EC2 instance type."
  }
}

variable "node_min_size" {
  description = "Minimum number of EKS worker nodes."
  type        = number
  default     = 1

  validation {
    condition     = var.node_min_size >= 0 && floor(var.node_min_size) == var.node_min_size
    error_message = "node_min_size must be a non-negative integer."
  }
}

variable "node_desired_size" {
  description = "Desired number of EKS worker nodes."
  type        = number
  default     = 2

  validation {
    condition     = var.node_desired_size >= 0 && floor(var.node_desired_size) == var.node_desired_size
    error_message = "node_desired_size must be a non-negative integer."
  }

  validation {
    condition = (
      var.node_desired_size >= var.node_min_size &&
      var.node_desired_size <= var.node_max_size
    )
    error_message = "node_desired_size must be between node_min_size and node_max_size."
  }
}

variable "node_max_size" {
  description = "Maximum number of EKS worker nodes."
  type        = number
  default     = 3

  validation {
    condition     = var.node_max_size >= 1 && floor(var.node_max_size) == var.node_max_size
    error_message = "node_max_size must be a positive integer."
  }
}

variable "extra_tags" {
  description = "Additional AWS tags. Repository governance tags cannot be overridden."
  type        = map(string)
  default     = {}
}
