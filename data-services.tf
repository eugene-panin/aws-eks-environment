data "aws_caller_identity" "current" {}

locals {
  application_bucket_name = coalesce(
    var.application_bucket_name,
    "${trim(substr(local.name_prefix, 0, 48), "-")}-${data.aws_caller_identity.current.account_id}"
  )

  application_bucket_policy = {
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.application.arn,
          "${aws_s3_bucket.application.arn}/*"
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      }
    ]
  }
}

resource "aws_security_group" "database" {
  name_prefix = "${local.name_prefix}-database-"
  description = "PostgreSQL access from EKS worker nodes"
  vpc_id      = aws_vpc.this.id

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-database"
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "database_from_eks" {
  security_group_id            = aws_security_group.database.id
  referenced_security_group_id = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
  description                  = "PostgreSQL from EKS cluster security group"
  from_port                    = 5432
  ip_protocol                  = "tcp"
  to_port                      = 5432
}

resource "aws_db_subnet_group" "main" {
  name       = "${local.name_prefix}-database"
  subnet_ids = values(aws_subnet.data)[*].id

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-database"
  })
}

resource "aws_db_instance" "main" {
  identifier = "${local.name_prefix}-postgres"

  engine         = "postgres"
  engine_version = var.database_engine_version
  instance_class = var.database_instance_class

  db_name  = var.database_name
  username = var.database_username
  port     = 5432

  manage_master_user_password = true

  allocated_storage     = var.database_allocated_storage_gib
  max_allocated_storage = var.database_max_allocated_storage_gib
  storage_type          = "gp3"
  storage_encrypted     = true

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.database.id]
  publicly_accessible    = false
  multi_az               = var.database_multi_az

  backup_retention_period   = var.database_backup_retention_days
  copy_tags_to_snapshot     = true
  deletion_protection       = var.database_deletion_protection
  skip_final_snapshot       = var.database_skip_final_snapshot
  final_snapshot_identifier = var.database_skip_final_snapshot ? null : var.database_final_snapshot_identifier

  auto_minor_version_upgrade      = false
  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-postgres"
  })

  lifecycle {
    precondition {
      condition     = var.database_skip_final_snapshot || var.database_final_snapshot_identifier != null
      error_message = "Set database_final_snapshot_identifier when database_skip_final_snapshot is false."
    }
  }
}

resource "aws_s3_bucket" "application" {
  bucket        = local.application_bucket_name
  force_destroy = var.application_bucket_force_destroy

  tags = merge(local.common_tags, {
    Name = local.application_bucket_name
  })
}

resource "aws_s3_bucket_ownership_controls" "application" {
  bucket = aws_s3_bucket.application.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "application" {
  bucket = aws_s3_bucket.application.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "application" {
  bucket = aws_s3_bucket.application.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "application" {
  bucket = aws_s3_bucket.application.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "application" {
  bucket = aws_s3_bucket.application.id

  rule {
    id     = "cost-control"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }

  depends_on = [aws_s3_bucket_versioning.application]
}

resource "aws_s3_bucket_policy" "application" {
  bucket = aws_s3_bucket.application.id

  policy = jsonencode(local.application_bucket_policy)
}
