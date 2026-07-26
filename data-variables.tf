variable "database_name" {
  description = "Initial PostgreSQL database name."
  type        = string
  default     = "application"

  validation {
    condition     = can(regex("^[a-z][a-z0-9_]{0,62}$", var.database_name))
    error_message = "database_name must be a valid PostgreSQL identifier with at most 63 characters."
  }
}

variable "database_username" {
  description = "PostgreSQL administrator username. The password is generated and stored by AWS Secrets Manager."
  type        = string
  default     = "application_admin"

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_]{0,62}$", var.database_username))
    error_message = "database_username must be a valid PostgreSQL identifier with at most 63 characters."
  }
}

variable "database_engine_version" {
  description = "PostgreSQL engine version available in the selected AWS region."
  type        = string
  default     = "17.10"
}

variable "database_instance_class" {
  description = "RDS instance class. The default is cost-conscious and not sized for production traffic."
  type        = string
  default     = "db.t4g.micro"
}

variable "database_allocated_storage_gib" {
  description = "Initial gp3 database storage in GiB."
  type        = number
  default     = 20

  validation {
    condition     = var.database_allocated_storage_gib >= 20
    error_message = "database_allocated_storage_gib must be at least 20 GiB for gp3."
  }
}

variable "database_max_allocated_storage_gib" {
  description = "Storage autoscaling ceiling in GiB."
  type        = number
  default     = 100

  validation {
    condition     = var.database_max_allocated_storage_gib >= var.database_allocated_storage_gib
    error_message = "database_max_allocated_storage_gib must not be lower than the initial allocation."
  }
}

variable "database_multi_az" {
  description = "Run a synchronous standby in another AZ. Recommended for production and disabled here to keep the demo affordable."
  type        = bool
  default     = false
}

variable "database_deletion_protection" {
  description = "Protect the database from accidental deletion. Enable for long-lived environments."
  type        = bool
  default     = false
}

variable "database_skip_final_snapshot" {
  description = "Skip a final snapshot during destroy. Convenient for an ephemeral demo; disable for long-lived environments."
  type        = bool
  default     = true
}

variable "database_final_snapshot_identifier" {
  description = "Unique final snapshot name required when database_skip_final_snapshot is false."
  type        = string
  default     = null
  nullable    = true

  validation {
    condition = (
      var.database_final_snapshot_identifier == null ||
      can(regex("^[a-z][a-z0-9-]{0,62}$", var.database_final_snapshot_identifier))
    )
    error_message = "database_final_snapshot_identifier must start with a lowercase letter and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "database_backup_retention_days" {
  description = "Number of days to retain automated database backups."
  type        = number
  default     = 7

  validation {
    condition     = var.database_backup_retention_days >= 1 && var.database_backup_retention_days <= 35
    error_message = "database_backup_retention_days must be between 1 and 35."
  }
}

variable "application_bucket_name" {
  description = "Optional globally unique S3 bucket name. A name using the AWS account ID is generated when null."
  type        = string
  default     = null
  nullable    = true
}

variable "application_bucket_force_destroy" {
  description = "Allow Terraform to delete a non-empty application bucket. Keep false outside disposable environments."
  type        = bool
  default     = false
}
