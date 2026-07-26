mock_provider "aws" {
  mock_data "aws_availability_zones" {
    defaults = {
      names = ["eu-west-1a", "eu-west-1b", "eu-west-1c"]
    }
  }

  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }

  mock_data "aws_partition" {
    defaults = {
      partition = "aws"
    }
  }

  mock_data "aws_eks_addon_version" {
    defaults = {
      version = "v1.0.0-eksbuild.1"
    }
  }
}

run "cost_aware_secure_defaults" {
  command = plan

  variables {
    expected_aws_account_id = "123456789012"
    admin_principal_arn     = "arn:aws:iam::123456789012:role/platform-admin"
  }

  assert {
    condition     = length(aws_subnet.public) == 3 && length(aws_subnet.private) == 3 && length(aws_subnet.data) == 3
    error_message = "The environment must spread public, worker, and data tiers across three availability zones."
  }

  assert {
    condition     = length(aws_nat_gateway.this) == 1
    error_message = "The cost-aware default must use one NAT gateway."
  }

  assert {
    condition     = aws_eks_cluster.this.access_config[0].authentication_mode == "API"
    error_message = "EKS authentication must use access entries instead of the legacy aws-auth ConfigMap."
  }

  assert {
    condition = (
      aws_eks_cluster.this.vpc_config[0].endpoint_private_access &&
      !aws_eks_cluster.this.vpc_config[0].endpoint_public_access
    )
    error_message = "The default EKS API endpoint must be private-only."
  }

  assert {
    condition     = !aws_eks_cluster.this.access_config[0].bootstrap_cluster_creator_admin_permissions
    error_message = "Implicit cluster-creator administrator access must be disabled by default."
  }

  assert {
    condition     = aws_eks_access_entry.admin.principal_arn == "arn:aws:iam::123456789012:role/platform-admin"
    error_message = "Cluster administrator access must be granted through an explicit access entry."
  }

  assert {
    condition = (
      length(aws_vpc_security_group_ingress_rule.eks_api_private) == 1 &&
      aws_vpc_security_group_ingress_rule.eks_api_private["10.40.0.0/16"].cidr_ipv4 == "10.40.0.0/16"
    )
    error_message = "The private EKS API must allow HTTPS from the VPC CIDR."
  }

  assert {
    condition = (
      aws_launch_template.eks_node.metadata_options[0].http_tokens == "required" &&
      aws_launch_template.eks_node.metadata_options[0].http_put_response_hop_limit == 1 &&
      aws_launch_template.eks_node.block_device_mappings[0].ebs[0].encrypted
    )
    error_message = "Worker nodes must require IMDSv2 and use encrypted root volumes."
  }

  assert {
    condition = (
      aws_db_instance.main.storage_encrypted &&
      !aws_db_instance.main.publicly_accessible &&
      aws_db_instance.main.manage_master_user_password &&
      !aws_db_instance.main.auto_minor_version_upgrade &&
      aws_db_instance.main.backup_retention_period >= 7
    )
    error_message = "PostgreSQL must be private, encrypted, backed up, version-controlled, and use an AWS-managed password."
  }

  assert {
    condition = (
      aws_s3_bucket_public_access_block.application.block_public_acls &&
      aws_s3_bucket_public_access_block.application.block_public_policy &&
      aws_s3_bucket_public_access_block.application.ignore_public_acls &&
      aws_s3_bucket_public_access_block.application.restrict_public_buckets
    )
    error_message = "The application bucket must block every form of public access."
  }

  assert {
    condition     = aws_s3_bucket_versioning.application.versioning_configuration[0].status == "Enabled"
    error_message = "The application bucket must have versioning enabled."
  }

  assert {
    condition     = local.application_bucket_policy.Statement[0].Condition.Bool["aws:SecureTransport"] == "false"
    error_message = "The application bucket policy must reject plaintext transport."
  }

  assert {
    condition = (
      aws_vpc_endpoint.s3.vpc_endpoint_type == "Gateway" &&
      length(aws_route_table.private) + length(aws_route_table.data) == 6
    )
    error_message = "Private and data route tables must use the S3 gateway endpoint."
  }
}

run "ha_oriented_profile" {
  command = plan

  variables {
    expected_aws_account_id              = "123456789012"
    admin_principal_arn                  = "arn:aws:iam::123456789012:role/platform-admin"
    nat_gateway_mode                     = "one_per_az"
    database_multi_az                    = true
    database_deletion_protection         = true
    database_skip_final_snapshot         = false
    database_final_snapshot_identifier   = "aws-eks-environment-prod-final-20260726"
    cluster_endpoint_public_access_cidrs = ["198.51.100.10/32"]
  }

  assert {
    condition     = length(aws_nat_gateway.this) == 3
    error_message = "The high-availability profile must create one NAT gateway in each availability zone."
  }

  assert {
    condition = (
      aws_db_instance.main.multi_az &&
      aws_db_instance.main.deletion_protection &&
      !aws_db_instance.main.skip_final_snapshot
    )
    error_message = "The high-availability profile must protect and replicate PostgreSQL."
  }

  assert {
    condition = (
      aws_eks_cluster.this.vpc_config[0].endpoint_public_access &&
      contains(aws_eks_cluster.this.vpc_config[0].public_access_cidrs, "198.51.100.10/32")
    )
    error_message = "Public EKS API access must be explicitly restricted to the configured CIDR."
  }
}

run "reject_noncanonical_unrestricted_cluster_endpoint" {
  command = plan

  variables {
    expected_aws_account_id              = "123456789012"
    admin_principal_arn                  = "arn:aws:iam::123456789012:role/platform-admin"
    cluster_endpoint_public_access_cidrs = ["1.2.3.4/0"]
  }

  expect_failures = [var.cluster_endpoint_public_access_cidrs]
}

run "require_final_snapshot_name" {
  command = plan

  variables {
    expected_aws_account_id      = "123456789012"
    admin_principal_arn          = "arn:aws:iam::123456789012:role/platform-admin"
    database_skip_final_snapshot = false
  }

  expect_failures = [aws_db_instance.main]
}
